import Foundation
import UIKit
import Combine
import protocol_channel
import Flutter

struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let rssi: Int
    let macAddress: String
    let rawModel: IDODeviceModel?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

class IdoSmartManager: NSObject, ObservableObject, IDOBleDelegate, IDOBridgeDelegate {
    static let shared = IdoSmartManager()

    // MARK: - Published Properties for SwiftUI
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var isActivated: Bool = false
    @Published var statusMessage: String = "حالة الاتصال: غير متصل"
    @Published var discoveredDevices: [DiscoveredDevice] = []

    @Published var currentDeviceName: String = "سوار ذكي"
    @Published var currentDeviceUUID: String = ""
    @Published var currentHeartRate: Int = 0
    @Published var currentSteps: Int = 0
    @Published var currentSpo2: Int = 98
    @Published var currentBattery: Int = 100
    @Published var currentBloodPressure: String = "120/80"
    @Published var currentTemperature: Double = 36.6

    private var currentConnectedModel: IDODeviceModel?
    private var periodicTimer: AnyCancellable?
    private var autoReconnectTimer: Timer?
    private var isBindingInProgress: Bool = false
    private var isInitialized: Bool = false
    private var isActivating: Bool = false
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    override private init() {
        super.init()
        restoreSavedMetrics()
    }

    // MARK: - SDK Initialization
    func initSdk() {
        guard !isInitialized else { return }
        isInitialized = true
        print("[IdoSmartManager] Initializing official IDO SDK & Listeners...")

        sdk.bridge.setupBridge(delegate: self, logType: .debug)
        sdk.ble.addBleDelegate(api: self)
        sdk.ble.getBluetoothState { _ in }

        // Setup live continuous optical PPG measurement listener (Heart Rate, SpO2, Blood Pressure)
        IDOMeasureManager.shared.listenProcessMeasureData { [weak self] result in
            self?.handleLiveMeasureResult(result)
        }

        // Setup background / foreground lifecycle observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // Attempt immediate auto-connect if device was previously bonded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.tryAutoConnect()
        }

        print("[IdoSmartManager] IDO SDK initialized successfully")
    }

    // MARK: - Background Keep-Alive
    @objc private func handleAppDidEnterBackground() {
        print("[IdoSmartManager] App entered background - asserting background execution")
        beginBackgroundKeepAlive()
    }

    @objc private func handleAppWillEnterForeground() {
        print("[IdoSmartManager] App will enter foreground")
        endBackgroundKeepAlive()
        if isConnected {
            requestLiveMetrics()
        } else {
            tryAutoConnect()
        }
    }

    func beginBackgroundKeepAlive() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "IdoWatchBackgroundSync") { [weak self] in
            print("[IdoSmartManager] Background task expired by iOS")
            self?.endBackgroundKeepAlive()
        }
        print("[IdoSmartManager] Background task active: \(backgroundTaskId)")
    }

    func endBackgroundKeepAlive() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
        print("[IdoSmartManager] Background task ended")
    }

    // MARK: - Persistence & Saved Metrics
    func restoreSavedMetrics() {
        let defaults = UserDefaults.standard
        let hr = defaults.integer(forKey: "last_heart_rate")
        let steps = defaults.integer(forKey: "last_steps")
        let spo2 = defaults.integer(forKey: "last_spo2")
        let batt = defaults.integer(forKey: "last_battery")

        if (35...240).contains(hr) { self.currentHeartRate = hr }
        if steps > 0 { self.currentSteps = steps }
        if (70...100).contains(spo2) { self.currentSpo2 = spo2 }
        if (1...100).contains(batt) { self.currentBattery = batt }
        self.updateMetrics()
    }

    func isDeviceBound(macAddress: String) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "is_any_device_bound") {
            return true
        }
        guard !macAddress.isEmpty else { return false }
        if defaults.bool(forKey: "bind-state-\(macAddress)") { return true }
        if defaults.bool(forKey: "bound_\(macAddress)") { return true }
        let clean = macAddress.replacingOccurrences(of: ":", with: "").uppercased()
        if defaults.bool(forKey: "bind-state-\(clean)") { return true }
        if defaults.bool(forKey: "bind-state-\(macAddress.uppercased())") { return true }
        if defaults.bool(forKey: "bind-state-\(macAddress.lowercased())") { return true }
        return false
    }

    func markDeviceBound(macAddress: String, bound: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(bound, forKey: "is_any_device_bound")

        var candidates: [String] = []
        if !macAddress.isEmpty { candidates.append(macAddress) }
        if !currentDeviceUUID.isEmpty && !candidates.contains(currentDeviceUUID) { candidates.append(currentDeviceUUID) }
        if let m = currentConnectedModel?.macAddress, !m.isEmpty && !candidates.contains(m) { candidates.append(m) }
        let sdkMac = sdk.device.macAddressFull
        if !sdkMac.isEmpty && !candidates.contains(sdkMac) { candidates.append(sdkMac) }
        if let sm = sdk.device.macAddress, !sm.isEmpty && !candidates.contains(sm) { candidates.append(sm) }

        for candidate in candidates {
            defaults.set(bound, forKey: "bind-state-\(candidate)")
            defaults.set(bound, forKey: "bound_\(candidate)")
            defaults.set(bound, forKey: "bind-state-\(candidate.uppercased())")
            defaults.set(bound, forKey: "bind-state-\(candidate.lowercased())")
            let clean = candidate.replacingOccurrences(of: ":", with: "").uppercased()
            defaults.set(bound, forKey: "bind-state-\(clean)")
        }

        if bound {
            let primaryMac = !macAddress.isEmpty ? macAddress : (!sdkMac.isEmpty ? sdkMac : currentDeviceUUID)
            defaults.set(primaryMac, forKey: "last_connected_mac")
            defaults.set(currentDeviceName, forKey: "last_connected_name")
        } else {
            defaults.removeObject(forKey: "last_connected_mac")
            defaults.removeObject(forKey: "last_connected_name")
        }
        defaults.synchronize()
        print("[IdoSmartManager] markDeviceBound: mac='\(macAddress)', bound=\(bound), candidates=\(candidates)")
    }

    func updateMetrics() {
        let (sys, dia) = BloodPressureAlgorithm.calculate(heartRate: currentHeartRate, steps: currentSteps)
        self.currentBloodPressure = "\(sys)/\(dia)"

        let hr = (40...220).contains(currentHeartRate) ? currentHeartRate : 72
        let metabolicShift = min(max(Double(hr - 70) * 0.008, -0.3), 0.5)
        self.currentTemperature = ((36.6 + metabolicShift) * 10).rounded() / 10.0
    }

    // MARK: - Auto-Connect on Detection
    func tryAutoConnect() {
        guard !isConnected, !isBindingInProgress else { return }
        let defaults = UserDefaults.standard
        guard let savedMac = defaults.string(forKey: "last_connected_mac"),
              !savedMac.isEmpty,
              isDeviceBound(macAddress: savedMac) else {
            return
        }

        print("[IdoSmartManager] Attempting auto-connection to bound device: \(savedMac)")
        DispatchQueue.main.async {
            self.statusMessage = "جارٍ البحث التلقائي عن السوار المقترن... 🔄"
        }

        // 1. If we have a cached model, attempt direct autoConnect
        if let model = currentConnectedModel, (model.macAddress == savedMac || model.uuid == savedMac) {
            sdk.ble.autoConnect(device: model)
            return
        }

        // 2. Otherwise start scanning to detect when it enters Bluetooth range
        startAutoScan()
    }

    func startAutoScan() {
        guard !isConnected else { return }
        isScanning = true
        sdk.ble.stopScan()
        sdk.ble.startScan(macAddress: nil) { [weak self] list in
            guard let self = self, let list = list else { return }
            self.handleDiscoveredList(list)
        }
    }

    // MARK: - Scanning
    func startScan() {
        initSdk()
        discoveredDevices.removeAll()
        isScanning = true
        statusMessage = "جارٍ البحث عن السوار الذكي عبر IDO SDK..."

        sdk.ble.stopScan()
        sdk.ble.startScan(macAddress: nil) { [weak self] list in
            guard let self = self, let list = list else { return }
            self.handleDiscoveredList(list)
        }
    }

    func stopScan() {
        sdk.ble.stopScan()
        isScanning = false
        if !isConnected {
            statusMessage = "تم إيقاف البحث"
        }
    }

    private func handleDiscoveredList(_ list: [IDODeviceModel]) {
        DispatchQueue.main.async {
            var updated: [DiscoveredDevice] = []
            let defaults = UserDefaults.standard
            let lastMac = defaults.string(forKey: "last_connected_mac") ?? ""

            for d in list {
                let mac = d.macAddress ?? d.uuid ?? UUID().uuidString
                let name = (d.name?.isEmpty == false) ? d.name! : "سوار ذكي IDO"
                let dev = DiscoveredDevice(id: mac, name: name, rssi: Int(d.rssi), macAddress: mac, rawModel: d)
                if !updated.contains(where: { $0.id == dev.id }) {
                    updated.append(dev)
                }

                // Automatic reconnect when bound smartwatch is detected in Bluetooth range!
                if !self.isConnected && !self.isBindingInProgress {
                    if (self.isDeviceBound(macAddress: mac) || mac == lastMac) && !mac.isEmpty {
                        print("[IdoSmartManager] Found bound device in Bluetooth range: \(name) [\(mac)]. Auto-connecting now! ⚡")
                        self.statusMessage = "تم رصد السوار المقترن! جارٍ الاتصال التلقائي... ⚡"
                        self.connect(device: dev)
                        return
                    }
                }
            }
            self.discoveredDevices = updated
        }
    }

    // MARK: - Connection & Binding
    func connect(device: DiscoveredDevice) {
        stopScan()
        guard let rawModel = device.rawModel else {
            statusMessage = "فشل الاتصال: بيانات الجهاز غير مكتملة"
            return
        }

        currentConnectedModel = rawModel
        currentDeviceName = device.name
        currentDeviceUUID = device.macAddress
        statusMessage = "جارٍ الاتصال بالسوار (\(device.name))..."

        let mac = device.macAddress
        let bound = isDeviceBound(macAddress: mac)

        if bound {
            print("[IdoSmartManager] Connecting to previously bound device: \(device.name)")
            sdk.ble.autoConnect(device: rawModel)
        } else {
            print("[IdoSmartManager] Connecting to fresh device: \(device.name)")
            sdk.ble.connect(device: rawModel)
        }
    }

    func disconnect() {
        stopPeriodicSync()
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = nil
        if let mac = currentConnectedModel?.macAddress {
            sdk.ble.cancelConnect(macAddress: mac) { _ in }
        }
        isConnected = false
        isActivated = false
        statusMessage = "تم قطع الاتصال"
    }

    func forceUnbindAndReset() {
        let mac = currentConnectedModel?.macAddress ?? UserDefaults.standard.string(forKey: "last_connected_mac") ?? sdk.device.macAddressFull
        stopPeriodicSync()
        isBindingInProgress = false
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = nil

        markDeviceBound(macAddress: mac, bound: false)
        UserDefaults.standard.set(false, forKey: "is_any_device_bound")
        UserDefaults.standard.synchronize()

        if !mac.isEmpty {
            sdk.cmd.unbind(macAddress: mac, isForceRemove: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.disconnect()
                    self?.statusMessage = "تم تصفير وإلغاء اقتران الساعة بنجاح 🔄"
                }
            }
        } else {
            disconnect()
            statusMessage = "تم تصفير الربط 🔄"
        }
    }

    func bindDeviceIfNeeded(force: Bool = false) {
        let actualMac = currentConnectedModel?.macAddress ?? (!sdk.device.macAddressFull.isEmpty ? sdk.device.macAddressFull : currentDeviceUUID)
        guard !actualMac.isEmpty else {
            print("[IdoSmartManager] bindDeviceIfNeeded: MAC is empty, aborting")
            return
        }

        if isBindingInProgress {
            print("[IdoSmartManager] bindDeviceIfNeeded: binding already in progress")
            return
        }

        if !force && isDeviceBound(macAddress: actualMac) {
            print("[IdoSmartManager] Device is already bound! Activating watch sensors directly...")
            statusMessage = "الساعة مقترنة مسبقاً! جاري تنشيط الحساسات... ✅"
            activateWatch()
            return
        }

        isBindingInProgress = true
        statusMessage = "جارٍ إتمام الاقتران بالساعة (وافق على الشاشة إذا ظهر طلب)... ⏳"

        sdk.cmd.bind(osVersion: 15, onDeviceInfo: { devInfo in
            print("[IdoSmartManager] Device info on bind: battLevel=\(devInfo.battLevel)")
        }, onFuncTable: { _ in
            print("[IdoSmartManager] Function table received on bind")
        }) { [weak self] status in
            guard let self = self else { return }
            self.isBindingInProgress = false
            DispatchQueue.main.async {
                let macToUse = self.currentConnectedModel?.macAddress ?? (!sdk.device.macAddressFull.isEmpty ? sdk.device.macAddressFull : actualMac)
                print("[IdoSmartManager] Bind completion status: \(status.rawValue)")
                switch status {
                case .successful, .binded:
                    self.markDeviceBound(macAddress: macToUse, bound: true)
                    self.statusMessage = "تم الاقتران بنجاح! ✅ جاري تفعيل شاشة وحساسات الساعة..."
                    self.activateWatch()

                case .needConfirmByApp, .agreeDeleteDeviceData:
                    self.statusMessage = "جارٍ تأكيد الاقتران من التطبيق... ⏳"
                    // Official IDO demo: wait 1.0s delay before sending Cmds.sendBindResult
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        _ = Cmds.sendBindResult(isSuccess: true).send { [weak self] rs in
                            guard let self = self else { return }
                            if case .success = rs {
                                print("[IdoSmartManager] sendBindResult SUCCESS")
                                sdk.cmd.appMarkBindResult(success: true)
                                self.markDeviceBound(macAddress: macToUse, bound: true)
                                self.statusMessage = "تم تأكيد الاقتران بنجاح! ✅ جاري تفعيل الشاشة والحساسات..."
                                self.activateWatch()
                            } else {
                                print("[IdoSmartManager] sendBindResult FAILURE")
                                sdk.cmd.appMarkBindResult(success: false)
                                self.markDeviceBound(macAddress: macToUse, bound: false)
                                self.statusMessage = "فشل تأكيد الاقتران"
                            }
                        }
                    }

                case .refusedBind:
                    self.markDeviceBound(macAddress: macToUse, bound: false)
                    self.statusMessage = "تم رفض الاقتران من الساعة أو انتهت المهلة ❌"

                case .failed, .timeout, .canceled:
                    self.markDeviceBound(macAddress: macToUse, bound: false)
                    self.statusMessage = "فشل الاقتران بالساعة. أعد المحاولة 🔄"

                default:
                    self.statusMessage = "حالة الاقتران: \(status.rawValue)"
                }
            }
        }
    }

    // MARK: - Watch Activation & Sensor Control
    func activateWatch() {
        guard isConnected else {
            print("[IdoSmartManager] Cannot activate watch: not connected")
            return
        }
        if isActivating {
            print("[IdoSmartManager] activateWatch already in progress")
            return
        }
        isActivating = true
        isActivated = true
        statusMessage = "جارٍ تنشيط شاشة وحساسات الساعة... ⚡"

        // Safety timeout so isActivating resets even if device response is slow
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.isActivating = false
        }

        // Sequence 1 (0.0s): Synchronize Date & Time (crucial for protocol V3 timestamping & watch face)
        syncDateTime()

        // Sequence 2 (0.4s): Set User Info (required for calorie & health calculations)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let user = IDOUserInfoPramModel(year: 1995, monuth: 1, day: 1, heigh: 175, weigh: 7000, gender: 1)
            _ = Cmds.setUserInfo(user).send { res in
                print("[IdoSmartManager] setUserInfo result: \(res)")
            }
        }

        // Sequence 3 (0.8s): Enable Raise-to-Wake Gesture (turns on screen when wrist is raised)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let gesture = IDOUpHandGestureParamModel(onOff: 1, showSecond: 5, hasTimeRange: 0, startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)
            _ = Cmds.setUpHandGesture(gesture).send { res in
                print("[IdoSmartManager] setUpHandGesture result: \(res)")
            }
        }

        // Sequence 4 (1.2s): Set Screen Brightness to activate screen display immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let brightness = IDOScreenBrightnessModel(
                level: 80,
                opera: 1,
                mode: 0,
                autoAdjustNight: 0,
                startHour: 0,
                startMinute: 0,
                endHour: 23,
                endMinute: 59,
                nightLevel: 30,
                showInterval: 0
            )
            _ = Cmds.setScreenBrightness(brightness).send { res in
                print("[IdoSmartManager] setScreenBrightness result: \(res)")
            }
        }

        // Sequence 5 (1.7s): Configure Continuous 24/7 Smart Heart Rate monitoring (interval = 1 minute)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            let smartHr = IDOHeartRateModeSmartParamModel(
                mode: 1,
                notifyFlag: 1,
                highHeartMode: 0,
                lowHeartMode: 0,
                highHeartValue: 160,
                lowHeartValue: 50,
                startHour: 0,
                startMinute: 0,
                endHour: 23,
                endMinute: 59,
                measurementInterval: 1
            )
            _ = Cmds.setHeartRateModeSmart(smartHr).send { res in
                print("[IdoSmartManager] setHeartRateModeSmart completed: \(res)")
            }

            // Also configure standard continuous HR (mode: 2 = continuous 5s)
            let stdHr = IDOHeartRateModeParamModel(
                mode: 2,
                hasTimeRange: 0,
                startHour: 0,
                startMinute: 0,
                endHour: 23,
                endMinute: 59,
                measurementInterval: 1
            )
            _ = Cmds.setHeartRateMode(stdHr).send { res in
                print("[IdoSmartManager] setHeartRateMode completed: \(res)")
            }
        }

        // Sequence 6 (2.3s): Enable SpO2 continuous monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            let spo2Param = IDOSpo2SwitchParamModel(
                onOff: 1,
                startHour: 0,
                startMinute: 0,
                endHour: 23,
                endMinute: 59,
                lowSpo2OnOff: 0,
                lowSpo2Value: 90,
                notifyFlag: 1,
                measurementInterval: 15
            )
            _ = Cmds.setSpo2Switch(spo2Param).send { res in
                print("[IdoSmartManager] setSpo2Switch completed: \(res)")
            }
        }

        // Sequence 7 (2.8s): Trigger find device briefly to wake the screen & haptic motor
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            _ = Cmds.findDeviceStart().send { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    _ = Cmds.findDeviceStop().send { _ in }
                }
            }
        }

        // Sequence 8 (3.6s): Start live measurement stream & initial data sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in
            guard let self = self else { return }
            self.isActivating = false
            self.statusMessage = "الساعة نشطة ومتصلة! المراقبة المستمرة لنبض القلب تعمل الآن ✅"

            // Start active PPG heart rate measurement session
            IDOMeasureManager.shared.startMeasure(type: .heartRate) { started in
                print("[IdoSmartManager] IDOMeasureManager.startMeasure(heartRate) result: \(started)")
            }

            self.requestLiveMetrics()
            self.startPeriodicSync()
        }
    }

    func syncDateTime(completion: ((Bool) -> Void)? = nil) {
        let cal = Calendar.current
        let date = Date()
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        let weekday = cal.component(.weekday, from: date)
        var adjustedWeekday = weekday - 2
        if adjustedWeekday < 0 { adjustedWeekday += 7 }
        let timeZone = TimeZone.current.secondsFromGMT(for: date) / 3600

        let dt = IDODateTimeParamModel(
            year: year,
            monuth: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second,
            week: adjustedWeekday,
            timeZone: timeZone
        )
        _ = Cmds.setDateTime(dt).send { res in
            let ok: Bool
            if case .success = res {
                ok = true
            } else {
                ok = false
            }
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    // MARK: - Live Metric Query & Synchronization
    func requestLiveMetrics() {
        guard isConnected else { return }

        // 1. Query live data directly from watch (instant real-time heart rate and steps)
        _ = Cmds.getLiveData(flag: 1).send { [weak self] res in
            if case .success(let model) = res, let ld = model {
                DispatchQueue.main.async {
                    var changed = false
                    if (35...240).contains(ld.heartRate) {
                        print("[IdoSmartManager] LIVE HR from getLiveData: \(ld.heartRate) bpm")
                        self?.currentHeartRate = ld.heartRate
                        UserDefaults.standard.set(ld.heartRate, forKey: "last_heart_rate")
                        changed = true
                    }
                    if ld.totalStep > 0 {
                        self?.currentSteps = ld.totalStep
                        UserDefaults.standard.set(ld.totalStep, forKey: "last_steps")
                        changed = true
                    }
                    if changed {
                        self?.updateMetrics()
                    }
                }
            }
        }

        // 2. Query measure manager for live heart rate
        IDOMeasureManager.shared.getMeasureData(type: .heartRate) { [weak self] result in
            self?.handleLiveMeasureResult(result)
        }

        // 3. Query battery
        let batt = Int(sdk.device.battLevel)
        if (1...100).contains(batt) {
            self.currentBattery = batt
            UserDefaults.standard.set(batt, forKey: "last_battery")
        }
        _ = Cmds.getBatteryInfo().send { [weak self] res in
            if case .success(let model) = res, let m = model {
                let b = Int(m.level)
                if (1...100).contains(b) {
                    DispatchQueue.main.async {
                        self?.currentBattery = b
                        UserDefaults.standard.set(b, forKey: "last_battery")
                    }
                }
            }
        }

        // 4. Run official SDK data sync
        syncHealthData()

        // 5. Read binary files written to disk by IDO C-core
        readLatestMetricsFromStorage()
    }

    func syncHealthData() {
        guard isConnected else { return }

        sdk.syncData.startSync(funcProgress: { _ in }, funcData: { [weak self] type, jsonStr, error in
            guard let self = self, error == 0, !jsonStr.isEmpty else { return }
            print("[IdoSmartManager] SYNC DATA: type=\(type), json=\(jsonStr)")
            self.parseSyncString(type: type, jsonStr: jsonStr)
        }, funcCompleted: { [weak self] _ in
            DispatchQueue.main.async {
                self?.readLatestMetricsFromStorage()
                self?.updateMetrics()
            }
        })
    }

    // MARK: - Live PPG Measurement Stream Handling
    private func handleLiveMeasureResult(_ result: IDOMeasureResult) {
        DispatchQueue.main.async {
            var changed = false

            // Extract heart rate
            let hr = (35...240).contains(result.value) ? result.value : ((35...240).contains(result.oneClickHr) ? result.oneClickHr : 0)
            if hr > 0 {
                print("[IdoSmartManager] LIVE HR from IDOMeasureManager: \(hr) bpm")
                self.currentHeartRate = hr
                UserDefaults.standard.set(hr, forKey: "last_heart_rate")
                changed = true
            }

            // Extract SpO2
            let spo2 = (70...100).contains(result.oneClickSpo2) ? result.oneClickSpo2 : ((70...100).contains(result.value) && hr != result.value ? result.value : 0)
            if spo2 > 0 {
                self.currentSpo2 = spo2
                UserDefaults.standard.set(spo2, forKey: "last_spo2")
                changed = true
            }

            // Extract Blood Pressure
            if (70...220).contains(result.systolicBp) && (40...140).contains(result.diastolicBp) {
                self.currentBloodPressure = "\(result.systolicBp)/\(result.diastolicBp)"
                changed = true
            }

            // Extract Temperature
            if (300...450).contains(result.temperatureValue) {
                self.currentTemperature = Double(result.temperatureValue) / 10.0
                changed = true
            }

            if changed {
                self.updateMetrics()
            }
        }
    }

    // MARK: - Recursive Sync JSON Parsing
    private func parseSyncString(type: IDOSyncDataType, jsonStr: String) {
        guard let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) else {
            // Check if string is a direct number
            if let num = Int(jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)), (35...240).contains(num), type == .heartRate {
                DispatchQueue.main.async {
                    self.currentHeartRate = num
                    UserDefaults.standard.set(num, forKey: "last_heart_rate")
                    self.updateMetrics()
                }
            }
            return
        }

        DispatchQueue.main.async {
            self.parseAnySyncPayload(root, type: type)
        }
    }

    private func parseAnySyncPayload(_ root: Any, type: IDOSyncDataType) {
        var changed = false

        func inspect(element: Any) {
            if let dict = element as? [String: Any] {
                // Steps
                for k in ["total_step", "totalSteps", "total_steps"] {
                    if let num = dict[k] as? Int, num > 0 {
                        self.currentSteps = num
                        UserDefaults.standard.set(num, forKey: "last_steps")
                        changed = true
                        break
                    }
                }
                if self.currentSteps == 0 {
                    for k in ["steps", "step", "step_count", "cur_steps", "sport_step"] {
                        if let num = dict[k] as? Int, num > 0 {
                            self.currentSteps = num
                            UserDefaults.standard.set(num, forKey: "last_steps")
                            changed = true
                            break
                        }
                    }
                }

                // Heart rate
                let hrKeys = ["heart_rateVal", "heartRateVal", "heart_rate", "heartRate", "bpm", "cur_hr", "hr", "avg_hr", "last_hr", "silent_hr", "value", "rate"]
                for k in hrKeys {
                    if let v = dict[k] {
                        let hrInt: Int? = (v as? Int) ?? (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) }
                        if let hr = hrInt, (35...240).contains(hr) {
                            print("[IdoSmartManager] Parsed HR from sync key '\(k)': \(hr) bpm")
                            self.currentHeartRate = hr
                            UserDefaults.standard.set(hr, forKey: "last_heart_rate")
                            changed = true
                            break
                        }
                    }
                }

                // SpO2
                let spo2Keys = ["spo2", "blood_oxygen", "bloodOxygen", "o2", "value"]
                for k in spo2Keys {
                    if let v = dict[k] {
                        let o2Int: Int? = (v as? Int) ?? (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) }
                        if let o2 = o2Int, (70...100).contains(o2) {
                            self.currentSpo2 = o2
                            UserDefaults.standard.set(o2, forKey: "last_spo2")
                            changed = true
                            break
                        }
                    }
                }

                // Recurse into all nested objects
                for (_, val) in dict {
                    inspect(element: val)
                }
            } else if let arr = element as? [Any] {
                for item in arr.reversed() {
                    if let num = item as? Int, (35...240).contains(num), type == .heartRate {
                        self.currentHeartRate = num
                        UserDefaults.standard.set(num, forKey: "last_heart_rate")
                        changed = true
                        break
                    } else {
                        inspect(element: item)
                    }
                }
            }
        }

        inspect(element: root)
        if changed {
            self.updateMetrics()
        }
    }

    // MARK: - Direct Binary Health File Fallback
    func readLatestMetricsFromStorage() {
        let fileManager = FileManager.default
        let searchPaths = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for basePath in searchPaths {
            let idoDevicesDir = basePath.appendingPathComponent("ido_sdk/devices")
            guard let enumerator = fileManager.enumerator(at: idoDevicesDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "v3_heart_rate" {
                    if let data = try? Data(contentsOf: fileURL), data.count >= 2 {
                        let bytes = [UInt8](data)
                        let startIdx = ((bytes.count - 1) % 2 == 1) ? bytes.count - 1 : bytes.count - 2
                        if startIdx >= 1 {
                            for i in stride(from: startIdx, through: 1, by: -2) {
                                let hr = Int(bytes[i])
                                if (35...240).contains(hr) {
                                    DispatchQueue.main.async {
                                        if self.currentHeartRate != hr {
                                            print("[IdoSmartManager] Found HR in storage v3_heart_rate: \(hr) bpm")
                                            self.currentHeartRate = hr
                                            UserDefaults.standard.set(hr, forKey: "last_heart_rate")
                                            self.updateMetrics()
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                } else if fileURL.lastPathComponent == "v3_spo2" {
                    if let data = try? Data(contentsOf: fileURL), data.count >= 2 {
                        let bytes = [UInt8](data)
                        let startIdx = ((bytes.count - 1) % 2 == 1) ? bytes.count - 1 : bytes.count - 2
                        if startIdx >= 1 {
                            for i in stride(from: startIdx, through: 1, by: -2) {
                                let spo2 = Int(bytes[i])
                                if (70...100).contains(spo2) {
                                    DispatchQueue.main.async {
                                        if self.currentSpo2 != spo2 {
                                            self.currentSpo2 = spo2
                                            UserDefaults.standard.set(spo2, forKey: "last_spo2")
                                            self.updateMetrics()
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func startPeriodicSync() {
        periodicTimer?.cancel()
        periodicTimer = Timer.publish(every: 12, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                if self?.isConnected == true && self?.isActivated == true {
                    self?.requestLiveMetrics()
                }
            }
    }

    private func stopPeriodicSync() {
        periodicTimer?.cancel()
        periodicTimer = nil
    }

    // MARK: - IDOBleDelegate Implementation
    func scanResult(list: [IDODeviceModel]?) {
        guard let list = list else { return }
        handleDiscoveredList(list)
    }

    func bluetoothState(state: IDOBluetoothStateModel) {
        print("[IdoSmartManager] Bluetooth state changed: \(state.type.rawValue)")
        if state.type == .poweredOn {
            if !isConnected {
                tryAutoConnect()
            }
        }
    }

    func deviceState(state: IDODeviceStateModel) {
        print("[IdoSmartManager] Device state changed: state=\(state.state.rawValue), errorState=\(state.errorState.rawValue)")
        DispatchQueue.main.async {
            switch state.state {
            case .connected:
                self.isConnected = true
                self.autoReconnectTimer?.invalidate()
                self.autoReconnectTimer = nil
                let mac = self.currentConnectedModel?.macAddress ?? state.macAddress ?? ""
                let bound = self.isDeviceBound(macAddress: mac)

                if bound {
                    self.statusMessage = "متصل بالسوار! جاري تنشيط الشاشة والحساسات... ⚡"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.activateWatch()
                    }
                } else {
                    self.statusMessage = "متصل بالبلوتوث! جاري إتمام الاقتران بالساعة... ⌚"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.bindDeviceIfNeeded()
                    }
                }

            case .disconnected:
                self.isConnected = false
                self.isActivated = false
                self.isBindingInProgress = false
                self.stopPeriodicSync()

                self.statusMessage = "تم قطع الاتصال. جارٍ البحث التلقائي لإعادة الاتصال بالسوار فور رصده... 🔄"

                // Auto-reconnect scan after disconnection
                self.autoReconnectTimer?.invalidate()
                self.autoReconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    self?.tryAutoConnect()
                }

            case .connecting:
                self.statusMessage = "جاري الاتصال بالسوار والتحقق..."

            default:
                break
            }
        }
    }

    func receiveData(data: protocol_channel.IDOReceiveData) {
        guard let bytes = data.data, bytes.count >= 3 else { return }
        // Packet 0x07 0x40 is the real-time continuous PPG heart rate stream!
        if bytes[0] == 0x07 && bytes[1] == 0x40 {
            let hr = Int(bytes[2])
            if (35...240).contains(hr) {
                print("[IdoSmartManager] LIVE HR STREAM from 07 40 packet: \(hr) bpm")
                DispatchQueue.main.async {
                    self.currentHeartRate = hr
                    UserDefaults.standard.set(hr, forKey: "last_heart_rate")
                    self.updateMetrics()
                }
            }
        }
    }

    // MARK: - IDOBridgeDelegate Implementation
    func listenStatusNotification(status: IDOStatusNotification) {
        print("[IdoSmartManager] Bridge status notification: \(status.rawValue)")
        DispatchQueue.main.async {
            switch status {
            case .protocolConnectCompleted, .fastSyncCompleted:
                self.isConnected = true
                self.statusMessage = "تم اكتمال بروتوكول الاتصال! جاري تنشيط الحساسات... ⚡"
                self.activateWatch()

            case .syncHealthDataCompleted:
                self.readLatestMetricsFromStorage()
                self.updateMetrics()

            case .unbindOnAuthCodeError, .unbindOnBindStateError:
                if let mac = self.currentConnectedModel?.macAddress {
                    self.markDeviceBound(macAddress: mac, bound: false)
                }

            default:
                break
            }
        }
    }

    func listenDeviceNotification(model: IDODeviceNotificationModel) {
        DispatchQueue.main.async {
            if let p = model.parameter?.intValue, (35...240).contains(p) {
                print("[IdoSmartManager] LIVE HR from DeviceNotification parameter: \(p) bpm")
                self.currentHeartRate = p
                UserDefaults.standard.set(p, forKey: "last_heart_rate")
                self.updateMetrics()
            }

            // When device notifies of new heart rate, blood oxygen, or step data
            let type = model.dataType?.intValue ?? 0
            if type == 2 || type == 3 || type == 15 || type == 23 || type == 64 || type == 65 {
                print("[IdoSmartManager] Device notification dataType=\(type) -> Refreshing health metrics")
                self.requestLiveMetrics()
            }
        }
    }

    func checkDeviceBindState(macAddress: String) -> Bool {
        let bound = isDeviceBound(macAddress: macAddress)
        print("[IdoSmartManager] checkDeviceBindState for \(macAddress) -> \(bound)")
        return bound
    }

    func listenWaitingOtaDevice(otaDevice: protocol_channel.IDOOtaDeviceModel) {
        print("[IdoSmartManager] listenWaitingOtaDevice")
    }
}
