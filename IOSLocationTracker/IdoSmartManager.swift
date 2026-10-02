import Foundation
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
    private var isBindingInProgress: Bool = false
    private var isInitialized: Bool = false

    override private init() {
        super.init()
        restoreSavedMetrics()
    }

    // MARK: - SDK Initialization
    func initSdk() {
        guard !isInitialized else { return }
        isInitialized = true
        print("[IdoSmartManager] Initializing official IDO SDK...")

        sdk.bridge.setupBridge(delegate: self, logType: .debug)
        sdk.ble.addBleDelegate(api: self)
        sdk.ble.getBluetoothState { _ in }

        print("[IdoSmartManager] IDO SDK initialized successfully")
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
        guard !macAddress.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: "bound_\(macAddress)")
    }

    func markDeviceBound(macAddress: String, bound: Bool) {
        guard !macAddress.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.set(bound, forKey: "bound_\(macAddress)")
        if bound {
            defaults.set(macAddress, forKey: "last_connected_mac")
        }
    }

    func updateMetrics() {
        let (sys, dia) = BloodPressureAlgorithm.calculate(heartRate: currentHeartRate, steps: currentSteps)
        self.currentBloodPressure = "\(sys)/\(dia)"

        let hr = (40...220).contains(currentHeartRate) ? currentHeartRate : 72
        let metabolicShift = min(max(Double(hr - 70) * 0.008, -0.3), 0.5)
        self.currentTemperature = ((36.6 + metabolicShift) * 10).rounded() / 10.0
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
            for d in list {
                let mac = d.macAddress ?? d.uuid ?? UUID().uuidString
                let name = (d.name?.isEmpty == false) ? d.name! : "IDO Smartwatch"
                let dev = DiscoveredDevice(id: mac, name: name, rssi: Int(d.rssi), macAddress: mac, rawModel: d)
                if !updated.contains(where: { $0.id == dev.id }) {
                    updated.append(dev)
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
        if let mac = currentConnectedModel?.macAddress {
            sdk.ble.cancelConnect(macAddress: mac) { _ in }
        }
        isConnected = false
        isActivated = false
        statusMessage = "تم قطع الاتصال"
    }

    func forceUnbindAndReset() {
        let mac = currentConnectedModel?.macAddress ?? UserDefaults.standard.string(forKey: "last_connected_mac") ?? ""
        stopPeriodicSync()
        isBindingInProgress = false

        if !mac.isEmpty {
            markDeviceBound(macAddress: mac, bound: false)
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
        guard let model = currentConnectedModel, let mac = model.macAddress, !mac.isEmpty else {
            return
        }

        if isBindingInProgress { return }

        if !force && isDeviceBound(macAddress: mac) {
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
                switch status {
                case .successful, .binded:
                    self.markDeviceBound(macAddress: mac, bound: true)
                    sdk.cmd.appMarkBindResult(success: true)
                    self.statusMessage = "تم الاقتران بنجاح! ✅ جاري تفعيل الحساسات..."
                    self.activateWatch()

                case .needConfirmByApp, .agreeDeleteDeviceData:
                    _ = Cmds.sendBindResult(true) { _, _ in
                        sdk.cmd.appMarkBindResult(success: true)
                        self.markDeviceBound(macAddress: mac, bound: true)
                        self.statusMessage = "تم تأكيد الاقتران بنجاح! ✅"
                        self.activateWatch()
                    }

                case .refusedBind:
                    self.markDeviceBound(macAddress: mac, bound: false)
                    self.statusMessage = "تم رفض الاقتران من الساعة أو انتهت المهلة ❌"

                case .failed, .timeout, .canceled:
                    self.markDeviceBound(macAddress: mac, bound: false)
                    self.statusMessage = "فشل الاقتران بالساعة. أعد المحاولة 🔄"

                default:
                    self.statusMessage = "حالة الاقتران: \(status.rawValue)"
                }
            }
        }
    }

    // MARK: - Watch Activation & Sensor Control
    func activateWatch() {
        guard isConnected else { return }
        isActivated = true
        statusMessage = "جارٍ تنشيط شاشة وحساسات الساعة... ⚡"

        // Step 1: Synchronize Date & Time (crucial for protocol V3 timestamping)
        syncDateTime { [weak self] _ in
            guard let self = self else { return }

            // Step 2: Set User Info
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let user = IDOUserInfoPramModel(year: 1995, monuth: 1, day: 1, heigh: 175, weigh: 70, gender: 1)
                _ = Cmds.setUserInfo(user) { _, _ in }
            }

            // Step 3: Enable Raise-to-Wake Gesture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                let gesture = IDOUpHandGestureParamModel(onOff: 1, showSecond: 5, hasTimeRange: 0, startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)
                _ = Cmds.setUpHandGesture(gesture) { _, _ in }
            }

            // Step 4: Configure Continuous 24/7 Smart Heart Rate monitoring
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                let hrParam = IDOHeartRateModeSmartParamModel(mode: 1, notifyFlag: 1, highHeartMode: 0, lowHeartMode: 0, highHeartValue: 160, lowHeartValue: 50, startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)
                _ = Cmds.setHeartRateModeSmart(hrParam) { _, _ in }
            }

            // Step 5: Enable SpO2 continuous monitoring
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let spo2Param = IDOSpo2SwitchParamModel(onOff: 1, startHour: 0, startMinute: 0, endHour: 23, endMinute: 59, lowSpo2OnOff: 0, lowSpo2Value: 90, notifyFlag: 1, measurementInterval: 15)
                _ = Cmds.setSpo2Switch(spo2Param) { _, _ in }
            }

            // Step 6: Wake screen briefly
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                _ = Cmds.findDeviceStart { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        _ = Cmds.findDeviceStop { _, _ in }
                    }
                }
            }

            // Step 7: Initial Data Sync & Start Periodic Polling
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                self.statusMessage = "الساعة متصلة والمراقبة المستمرة نشطة الآن ✅"
                self.syncHealthData()
                self.startPeriodicSync()
            }
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

        let dt = IDODateTimeParamModel(year: year, monuth: month, day: day, hour: hour, minute: minute, second: second, week: adjustedWeekday, timeZone: timeZone)
        _ = Cmds.setDateTime(dt) { err, _ in
            let ok = err.code == 0
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    // MARK: - Health Data Synchronization
    func syncHealthData() {
        guard isConnected else { return }

        // Read battery directly from SDK device state
        let batt = Int(sdk.device.battLevel)
        if batt > 0 && batt <= 100 {
            self.currentBattery = batt
            UserDefaults.standard.set(batt, forKey: "last_battery")
        }

        // Query detailed battery status
        _ = Cmds.getBatteryInfo { [weak self] err, model in
            if err.code == 0, let m = model {
                let b = Int(m.curEnergy)
                if (1...100).contains(b) {
                    DispatchQueue.main.async {
                        self?.currentBattery = b
                        UserDefaults.standard.set(b, forKey: "last_battery")
                    }
                }
            }
        }

        // Trigger official sync
        sdk.syncData.startSync(funcProgress: { _ in }, funcData: { [weak self] type, jsonStr, error in
            guard let self = self, error == 0, !jsonStr.isEmpty else { return }
            self.parseSyncJson(type: type, jsonStr: jsonStr)
        }, funcCompleted: { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMetrics()
            }
        })
    }

    private func parseSyncJson(type: IDOSyncDataType, jsonStr: String) {
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        DispatchQueue.main.async {
            var changed = false

            // Steps extraction
            for k in ["total_step", "totalSteps", "total_steps", "steps", "step_count", "cur_steps"] {
                if let v = json[k] as? Int, v > 0 {
                    self.currentSteps = v
                    UserDefaults.standard.set(v, forKey: "last_steps")
                    changed = true
                    break
                }
            }

            // Heart rate extraction
            if type == .heartRate {
                for k in ["heart_rateVal", "heartRateVal", "heart_rate", "heartRate", "bpm", "cur_hr", "value"] {
                    if let v = json[k] as? Int, (35...240).contains(v) {
                        self.currentHeartRate = v
                        UserDefaults.standard.set(v, forKey: "last_heart_rate")
                        changed = true
                        break
                    }
                }
            }

            // SpO2 extraction
            if type == .bloodOxygen {
                for k in ["spo2", "blood_oxygen", "bloodOxygen", "value"] {
                    if let v = json[k] as? Int, (70...100).contains(v) {
                        self.currentSpo2 = v
                        UserDefaults.standard.set(v, forKey: "last_spo2")
                        changed = true
                        break
                    }
                }
            }

            if changed {
                self.updateMetrics()
            }
        }
    }

    private func startPeriodicSync() {
        periodicTimer?.cancel()
        periodicTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                if self?.isConnected == true && self?.isActivated == true {
                    self?.syncHealthData()
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
    }

    func deviceState(state: IDODeviceStateModel) {
        print("[IdoSmartManager] Device state changed: state=\(state.state.rawValue), errorState=\(state.errorState.rawValue)")
        DispatchQueue.main.async {
            switch state.state {
            case .connected:
                self.isConnected = true
                let name = self.currentConnectedModel?.name ?? "الساعة الذكية"
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

                if state.errorState == .pairFail {
                    self.statusMessage = "فشل الاقتران. يرجى إلغاء حفظ الجهاز من إعدادات البلوتوث ثم المحاولة مجدداً."
                } else {
                    self.statusMessage = "حالة الاتصال: غير متصل"
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
                DispatchQueue.main.async {
                    self.currentHeartRate = hr
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
        if let paramStr = model.parameter, let p = Int(paramStr), (35...240).contains(p) {
            DispatchQueue.main.async {
                self.currentHeartRate = p
                self.updateMetrics()
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
