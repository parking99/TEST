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
    private var lastLiveSpo2Time: Date = Date.distantPast
    @Published var currentBattery: Int = 100
    @Published var currentBloodPressure: String = "120/80"
    @Published var currentTemperature: Double = 36.6

    var currentConnectedModel: IDODeviceModel?
    private var periodicTimer: AnyCancellable?
    private var healthSyncTimer: AnyCancellable?
    
    // Battery Hysteresis State
    private var pendingBatteryDropValue: Int = 0
    private var pendingBatteryDropConfirmCount: Int = 0
    
    private var autoReconnectTimer: Timer?
    private var isBindingInProgress: Bool = false
    private var isInitialized: Bool = false
    private var isActivating: Bool = false
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // Connection stability state
    private var connectTimeoutTimer: Timer?
    private var isConnectAttemptActive: Bool = false
    private var userInitiatedDisconnect: Bool = false
    private var reconnectAttempt: Int = 0
    private var autoScanToken: Int = 0
    private var activationToken: Int = 0
    private var lastActivationStart: Date = .distantPast
    private var bindWatchdogToken: Int = 0
    private var isSyncingHealth: Bool = false
    private var syncStartedAt: Date = .distantPast

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
            self?.scheduleReconnect(immediate: true)
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
            reconnectAttempt = 0
            scheduleReconnect(immediate: true)
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

        if (40...220).contains(hr) { self.currentHeartRate = hr }
        if steps > 0 { self.currentSteps = steps }
        // Physiologically valid SpO2 is 90% - 100%. Discard corrupted values (e.g. 76 HR collision)
        if (90...100).contains(spo2) {
            self.currentSpo2 = spo2
        } else {
            self.currentSpo2 = 98
            defaults.set(98, forKey: "last_spo2")
        }
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
        let sm = sdk.device.macAddress
        if !sm.isEmpty && !candidates.contains(sm) { candidates.append(sm) }

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
            if let u = currentConnectedModel?.uuid, !u.isEmpty {
                defaults.set(u, forKey: "last_connected_uuid")
            }
        } else {
            defaults.removeObject(forKey: "last_connected_mac")
            defaults.removeObject(forKey: "last_connected_name")
            defaults.removeObject(forKey: "last_connected_uuid")
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
        
        // Handle Daily Step Tracking & Reset
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())
        
        var stepDict: [String: Int] = [:]
        if let data = UserDefaults.standard.data(forKey: "daily_steps_history"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            stepDict = decoded
        }
        
        let lastDate = UserDefaults.standard.object(forKey: "last_steps_date") as? Date ?? Date()
        
        if !Calendar.current.isDateInToday(lastDate) {
            // New day detected! Reset steps
            self.currentSteps = 0
            UserDefaults.standard.set(0, forKey: "last_steps")
            UserDefaults.standard.set(Date(), forKey: "last_steps_date")
        } else {
            // Update today's steps in dictionary
            let savedToday = stepDict[todayStr] ?? 0
            if self.currentSteps > savedToday {
                stepDict[todayStr] = self.currentSteps
                if let encoded = try? JSONEncoder().encode(stepDict) {
                    UserDefaults.standard.set(encoded, forKey: "daily_steps_history")
                }
            }
            UserDefaults.standard.set(Date(), forKey: "last_steps_date")
        }
    }
    
    // MARK: - Device Identity Helpers
    private func normalizedId(_ s: String?) -> String {
        return (s ?? "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    private func hasSavedIdentity() -> Bool {
        let d = UserDefaults.standard
        return !normalizedId(d.string(forKey: "last_connected_mac")).isEmpty
            || !normalizedId(d.string(forKey: "last_connected_uuid")).isEmpty
    }

    /// True only if the given identifiers belong to the watch we previously paired with.
    private func matchesSavedDevice(mac: String?, uuid: String?) -> Bool {
        let d = UserDefaults.standard
        let savedMac = normalizedId(d.string(forKey: "last_connected_mac"))
        let savedUUID = normalizedId(d.string(forKey: "last_connected_uuid"))
        if savedMac.isEmpty && savedUUID.isEmpty { return false }
        let m = normalizedId(mac)
        let u = normalizedId(uuid)
        if !m.isEmpty && (m == savedMac || m == savedUUID) { return true }
        if !u.isEmpty && (u == savedMac || u == savedUUID) { return true }
        return false
    }

    /// Per-device bound check. The global "is_any_device_bound" flag alone is NOT enough:
    /// it would make a brand-new / someone else's watch look "already paired" and skip pairing.
    private func isBoundForCurrentDevice(fallbackMac: String? = nil) -> Bool {
        let mac = currentConnectedModel?.macAddress ?? fallbackMac ?? currentDeviceUUID
        guard isDeviceBound(macAddress: mac) else { return false }
        guard hasSavedIdentity() else { return true }   // legacy installs without saved identity
        return matchesSavedDevice(mac: mac, uuid: currentConnectedModel?.uuid)
            || matchesSavedDevice(mac: currentDeviceUUID, uuid: nil)
    }

    // MARK: - Auto-Connect on Detection
    func tryAutoConnect() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.tryAutoConnect() }
            return
        }
        guard !isConnected, !isBindingInProgress, !isConnectAttemptActive, !userInitiatedDisconnect else { return }
        let defaults = UserDefaults.standard
        guard let savedMac = defaults.string(forKey: "last_connected_mac"),
              !savedMac.isEmpty,
              isDeviceBound(macAddress: savedMac) else {
            return
        }

        print("[IdoSmartManager] Attempting auto-connection to bound device: \(savedMac)")
        statusMessage = "جارٍ البحث التلقائي عن السوار المقترن... 🔄"

        // 1. If we have a cached model of OUR watch, attempt direct autoConnect
        if let model = currentConnectedModel, matchesSavedDevice(mac: model.macAddress, uuid: model.uuid) {
            isConnectAttemptActive = true
            startConnectTimeout()
            sdk.ble.autoConnect(device: model)
            return
        }

        // 2. Otherwise start scanning to detect when it enters Bluetooth range
        startAutoScan()
    }

    /// Keeps trying to reconnect to the bonded watch with exponential backoff (2s, 2s, 4s, 8s, 16s, 30s...)
    /// until it is connected, the user disconnects on purpose, or the watch is unpaired.
    func scheduleReconnect(immediate: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.scheduleReconnect(immediate: immediate) }
            return
        }
        guard !isConnected, !userInitiatedDisconnect else { return }
        guard let savedMac = UserDefaults.standard.string(forKey: "last_connected_mac"), !savedMac.isEmpty else { return }

        autoReconnectTimer?.invalidate()
        let delay: TimeInterval = immediate ? 0.5 : min(max(pow(2.0, Double(reconnectAttempt)), 2.0), 30.0)
        reconnectAttempt = min(reconnectAttempt + 1, 10)
        print("[IdoSmartManager] Reconnect scheduled in \(delay)s (attempt \(reconnectAttempt))")

        autoReconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            self.tryAutoConnect()
            self.scheduleReconnect(immediate: false)   // keep the retry loop alive until connected
        }
    }

    /// Fails fast instead of hanging on "connecting..." forever.
    private func startConnectTimeout() {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            print("[IdoSmartManager] Connect attempt timed out - cancelling and retrying")
            if let mac = self.currentConnectedModel?.macAddress {
                sdk.ble.cancelConnect(macAddress: mac) { _ in }
            }
            self.isConnectAttemptActive = false
            self.connectTimeoutTimer = nil
            self.statusMessage = "انتهت مهلة الاتصال، جارٍ إعادة المحاولة... 🔄"
            self.scheduleReconnect(immediate: false)
        }
    }

    func startAutoScan() {
        guard !isConnected else { return }
        isScanning = true
        autoScanToken += 1
        let token = autoScanToken
        sdk.ble.stopScan()
        sdk.ble.startScan(macAddress: nil) { [weak self] list in
            guard let self = self, let list = list else { return }
            self.handleDiscoveredList(list)
        }
        // Don't scan forever (battery + radio contention). The reconnect loop restarts it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, token == self.autoScanToken, !self.isConnected, self.isScanning else { return }
            sdk.ble.stopScan()
            self.isScanning = false
        }
    }

    // MARK: - Scanning
    func startScan() {
        initSdk()
        userInitiatedDisconnect = false
        autoScanToken += 1   // invalidates any pending auto-scan stop
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
        autoScanToken += 1
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
                let name = (d.name?.isEmpty == false) ? d.name! : "سوار ذكي IDO"
                let dev = DiscoveredDevice(id: mac, name: name, rssi: Int(d.rssi), macAddress: mac, rawModel: d)
                if !updated.contains(where: { $0.id == dev.id }) {
                    updated.append(dev)
                }

                // Automatic reconnect ONLY to the watch we paired with (never to any bonded-looking device nearby)
                if !self.isConnected && !self.isBindingInProgress && !self.isConnectAttemptActive && !self.userInitiatedDisconnect {
                    if self.matchesSavedDevice(mac: d.macAddress, uuid: d.uuid) && !mac.isEmpty {
                        print("[IdoSmartManager] Found paired device in Bluetooth range: \(name) [\(mac)]. Auto-connecting now! ⚡")
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
        guard !isConnected else {
            print("[IdoSmartManager] connect ignored: already connected")
            return
        }
        stopScan()
        guard let rawModel = device.rawModel else {
            statusMessage = "فشل الاتصال: بيانات الجهاز غير مكتملة"
            return
        }

        userInitiatedDisconnect = false
        currentConnectedModel = rawModel
        currentDeviceName = device.name
        currentDeviceUUID = device.macAddress
        statusMessage = "جارٍ الاتصال بالسوار (\(device.name))..."

        isConnectAttemptActive = true
        startConnectTimeout()

        let bound = isBoundForCurrentDevice()

        if bound {
            print("[IdoSmartManager] Connecting to previously bound device: \(device.name)")
            sdk.ble.autoConnect(device: rawModel)
        } else {
            print("[IdoSmartManager] Connecting to fresh device: \(device.name)")
            sdk.ble.connect(device: rawModel)
        }
    }

    func disconnect() {
        userInitiatedDisconnect = true   // do NOT auto-reconnect after a deliberate disconnect
        activationToken += 1
        stopPeriodicSync()
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = nil
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        isConnectAttemptActive = false
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

        if !force && isBoundForCurrentDevice() {
            print("[IdoSmartManager] Device is already bound! Activating watch sensors directly...")
            statusMessage = "الساعة مقترنة مسبقاً! جاري تنشيط الحساسات... ✅"
            activateWatch(force: true)
            return
        }

        isBindingInProgress = true
        statusMessage = "جارٍ إتمام الاقتران بالساعة (وافق على الشاشة إذا ظهر طلب)... ⏳"

        // Watchdog: if the SDK never calls back, don't stay stuck in "binding" forever
        bindWatchdogToken += 1
        let bindToken = bindWatchdogToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self = self, self.bindWatchdogToken == bindToken, self.isBindingInProgress else { return }
            print("[IdoSmartManager] Bind watchdog fired - resetting binding state")
            self.isBindingInProgress = false
            self.statusMessage = "انتهت مهلة الاقتران. اضغط اتصال للمحاولة مرة أخرى 🔄"
        }

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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        self?.activateWatch(force: true)
                    }

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
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                                    self?.activateWatch(force: true)
                                }
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

    /// Runs `block` after `delay` only if this activation sequence is still the current one and the watch is still connected.
    /// Prevents stale command bursts from piling up on the BLE queue after reconnects / repeated triggers.
    private func afterActivation(_ delay: Double, token: Int, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.activationToken == token, self.isConnected else { return }
            block()
        }
    }

    func activateWatch(force: Bool = false) {
        guard isConnected else {
            print("[IdoSmartManager] Cannot activate watch: not connected")
            return
        }
        if isActivating && !force {
            print("[IdoSmartManager] activateWatch already in progress")
            return
        }
        // Debounce: several events (connected / protocolConnectCompleted / bind) fire within ~1s of each other.
        // Restarting the sequence for each one would send duplicate command bursts, unless forced.
        if isActivating && !force && Date().timeIntervalSince(lastActivationStart) < 2.5 {
            print("[IdoSmartManager] activateWatch debounced (sequence just started)")
            return
        }
        lastActivationStart = Date()
        activationToken += 1
        let token = activationToken
        isActivating = true
        isActivated = true
        statusMessage = "جارٍ تنشيط شاشة وحساسات الساعة... ⚡"



        // Immediately seed saved & storage metrics so the screen is populated without waiting
        restoreSavedMetrics()
        readLatestMetricsFromStorage()

        // Safety timeout so isActivating resets even if device response is slow
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.activationToken == token else { return }
            self.isActivating = false
        }

        // Sequence 1 (0.5s): Synchronize Date & Time (crucial for protocol V3 timestamping & watch face)
        afterActivation(0.5, token: token) {
            self.syncDateTime()
        }

        // Sequence 1.1 (1.0s): Set Screen Brightness to activate screen display
        afterActivation(1.0, token: token) {
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

        // Sequence 2 (1.3s): Set User Info (required for calorie & health calculations)
        afterActivation(1.3, token: token) {
            let user = IDOUserInfoPramModel(year: 1995, monuth: 1, day: 1, heigh: 175, weigh: 7000, gender: 1)
            _ = Cmds.setUserInfo(user).send { res in
                print("[IdoSmartManager] setUserInfo result: \(res)")
            }
        }

        // Sequence 3 (1.6s): Enable Raise-to-Wake Gesture (turns on screen when wrist is raised)
        afterActivation(1.6, token: token) {
            let gesture = IDOUpHandGestureParamModel(onOff: 1, showSecond: 5, hasTimeRange: 0, startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)
            _ = Cmds.setUpHandGesture(gesture).send { res in
                print("[IdoSmartManager] setUpHandGesture result: \(res)")
            }
        }



        // Sequence 5 (1.9s): Configure Continuous 24/7 Smart Heart Rate monitoring (interval = 1 minute)
        afterActivation(1.9, token: token) {
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

            // Configure Continuous 24/7 SpO2 monitoring for automatic background updates
            let spo2Switch = IDOSpo2SwitchParamModel(
                onOff: 1,
                startHour: 0,
                startMinute: 0,
                endHour: 23,
                endMinute: 59,
                lowSpo2OnOff: 0,
                lowSpo2Value: 90,
                notifyFlag: 1,
                measurementInterval: 1 // 1 minute interval for fastest updates
            )
            _ = Cmds.setSpo2Switch(spo2Switch).send { res in
                print("[IdoSmartManager] setSpo2Switch result: \(res)")
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

        // Sequence 6 (1.8s): Enable SpO2 continuous monitoring
        afterActivation(1.8, token: token) {
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

        // Sequence 7 (2.2s): Trigger find device briefly to wake the screen & haptic motor
        afterActivation(2.2, token: token) {
            _ = Cmds.findDeviceStart().send { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    _ = Cmds.findDeviceStop().send { _ in }
                }
            }
        }

        // Sequence 8 (2.8s): Start live measurement stream & initial data sync
        afterActivation(2.8, token: token) { [weak self] in
            guard let self = self else { return }
            self.isActivating = false
            self.statusMessage = "الساعة نشطة ومتصلة! المراقبة المستمرة لنبض القلب تعمل الآن ✅"

            // Start active PPG heart rate measurement session
            IDOMeasureManager.shared.startMeasure(type: .heartRate) { started in
                print("[IdoSmartManager] IDOMeasureManager.startMeasure(heartRate) result: \(started)")
            }

            self.readLatestMetricsFromStorage()
            self.requestLiveMetrics()
            self.startPeriodicSync()
            GoogleSheetSyncManager.shared.performAutoSync(force: true)
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

    // MARK: - Centralized Heart Rate Filter & Smoother
    func updateLiveHeartRate(_ rawHr: Int, source: String) {
        // Physiologically plausible range for resting to active human pulse
        guard (40...220).contains(rawHr) else { return }

        DispatchQueue.main.async {
            // Initial acquisition: immediately accept
            if self.currentHeartRate == 0 {
                print("[IdoSmartManager] Initial HR set to \(rawHr) bpm (source: \(source))")
                self.currentHeartRate = rawHr
                UserDefaults.standard.set(rawHr, forKey: "last_heart_rate")
                self.updateMetrics()
                return
            }

            let diff = abs(rawHr - self.currentHeartRate)

            // Outlier rejection & Exponential Moving Average (EMA) smoothing:
            // Prevents sudden wild spikes from optical noise, wrist motion artifacts, or packet collisions
            let smoothedHr: Int
            if diff > 25 {
                // Heavy damping for sudden jumps (>25 bpm in a single sample): 75% previous + 25% new
                smoothedHr = Int(round(Double(self.currentHeartRate) * 0.75 + Double(rawHr) * 0.25))
            } else if diff > 8 {
                // Moderate smoothing for medium changes: 60% previous + 40% new
                smoothedHr = Int(round(Double(self.currentHeartRate) * 0.60 + Double(rawHr) * 0.40))
            } else {
                // Small natural pulse variation: responsive update
                smoothedHr = rawHr
            }

            let finalHr = min(max(smoothedHr, 40), 220)
            if finalHr != self.currentHeartRate {
                print("[IdoSmartManager] Filtered HR: \(self.currentHeartRate) -> \(finalHr) (raw: \(rawHr), source: \(source))")
                self.currentHeartRate = finalHr
                UserDefaults.standard.set(finalHr, forKey: "last_heart_rate")
                self.updateMetrics()
            }
        }
    }

    // MARK: - Live Metric Query & Synchronization
    func requestLiveMetrics() {
        guard isConnected else { return }

        // Seed from storage if metrics are currently zero
        if currentHeartRate == 0 || currentSpo2 == 0 {
            readLatestMetricsFromStorage()
        }

        // 1. Query live data directly from watch (instant real-time heart rate and steps)
        _ = Cmds.getLiveData(flag: 1).send { [weak self] res in
            if case .success(let model) = res, let ld = model {
                DispatchQueue.main.async {
                    if (40...220).contains(ld.heartRate) {
                        self?.updateLiveHeartRate(ld.heartRate, source: "getLiveData")
                    }
                    if ld.totalStep >= 0 && ld.totalStep != self?.currentSteps {
                        self?.currentSteps = ld.totalStep
                        UserDefaults.standard.set(ld.totalStep, forKey: "last_steps")
                        self?.updateMetrics()
                    }
                }
            }
        }

        // Real-time HR and SpO2 are processed entirely via the listenProcessMeasureData callback.
        // Polling getMeasureData is explicitly documented to return static final values and interferes with the stream.

        // 3. Query battery
        _ = Cmds.getBatteryInfo().send { [weak self] res in
            if case .success(let model) = res, let m = model {
                let b = Int(m.level)
                // Documented charging status fields: 1=Charging, 2=Charging complete
                let isCharging = (m.status == 1 || m.status == 2)
                if (1...100).contains(b) {
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        
                        if self.currentBattery == 0 {
                            // Initial value
                            self.currentBattery = b
                        } else if isCharging && b > self.currentBattery {
                            // Accept increase immediately if charging
                            self.currentBattery = b
                            self.pendingBatteryDropConfirmCount = 0
                        } else if b < self.currentBattery {
                            // Require 2 consecutive confirmations to accept a drop
                            if self.pendingBatteryDropValue == b {
                                self.pendingBatteryDropConfirmCount += 1
                                if self.pendingBatteryDropConfirmCount >= 2 {
                                    self.currentBattery = b
                                    self.pendingBatteryDropConfirmCount = 0
                                }
                            } else {
                                self.pendingBatteryDropValue = b
                                self.pendingBatteryDropConfirmCount = 1
                            }
                        } else if b == self.currentBattery {
                            // Reset drop counter if we read the current value again
                            self.pendingBatteryDropConfirmCount = 0
                        }
                        
                        UserDefaults.standard.set(self.currentBattery, forKey: "last_battery")
                    }
                }
            }
        }
    }

    func syncHealthData() {
        guard isConnected else { return }

        // Never overlap syncs: a new startSync while one is running floods the BLE queue
        if isSyncingHealth && Date().timeIntervalSince(syncStartedAt) < 60 {
            return
        }
        isSyncingHealth = true
        syncStartedAt = Date()

        sdk.syncData.startSync(funcProgress: { _ in }, funcData: { [weak self] type, jsonStr, error in
            guard let self = self, error == 0, !jsonStr.isEmpty else { return }
            print("[IdoSmartManager] SYNC DATA: type=\(type), json=\(jsonStr)")
            self.parseSyncString(type: type, jsonStr: jsonStr)
        }, funcCompleted: { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSyncingHealth = false
                if self?.currentHeartRate == 0 {
                    self?.readLatestMetricsFromStorage()
                }
                self?.updateMetrics()
            }
        })
    }

    // MARK: - Live PPG Measurement Stream Handling
    private func handleLiveMeasureResult(_ result: IDOMeasureResult, type: IDOMeasureType? = nil) {
        #if DEBUG
        print("[IDO_TRACE] LIVE_STREAM | .value: \(result.value) | .oneClickHr: \(result.oneClickHr) | .oneClickSpo2: \(result.oneClickSpo2)")
        #endif
        DispatchQueue.main.async {
            var changed = false

            // Extract heart rate from the generic .value field (as this is the standard payload for live HR streams)
            // Note: SpO2 could theoretically multiplex here if initiated from watch, but HR is the primary continuous stream.
            let streamValue = result.value
            if streamValue > 0 && streamValue < 220 {
                // If it's a typical resting/active HR, update it.
                // (If it's exactly 95-100, it could be SpO2 from a watch trigger, but we favor HR for the continuous UI)
                self.updateLiveHeartRate(streamValue, source: "IDOMeasureResult.value")
            }

            // Extract SpO2 safely from oneClickSpo2 if available (e.g. during a combined measurement)
            if (90...100).contains(result.oneClickSpo2) {
                self.lastLiveSpo2Time = Date()
                if self.currentSpo2 != result.oneClickSpo2 {
                    self.currentSpo2 = result.oneClickSpo2
                    UserDefaults.standard.set(result.oneClickSpo2, forKey: "last_spo2")
                    changed = true
                }
            }

            // Extract Blood Pressure
            if (70...220).contains(result.systolicBp) && (40...140).contains(result.diastolicBp) {
                let bpStr = "\(result.systolicBp)/\(result.diastolicBp)"
                if self.currentBloodPressure != bpStr {
                    self.currentBloodPressure = bpStr
                    changed = true
                }
            }

            // Extract Temperature
            if (300...450).contains(result.temperatureValue) {
                let temp = Double(result.temperatureValue) / 10.0
                if self.currentTemperature != temp {
                    self.currentTemperature = temp
                    changed = true
                }
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
            if let num = Int(jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if (40...220).contains(num) && type == .heartRate {
                    self.updateLiveHeartRate(num, source: "syncDirectString")
                } else if (90...100).contains(num) && (type == .bloodOxygen) {
                    if self.currentSpo2 != num {
                        self.currentSpo2 = num
                        UserDefaults.standard.set(num, forKey: "last_spo2")
                        DispatchQueue.main.async { self.updateMetrics() }
                    }
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
                        if self.currentSteps != num {
                            self.currentSteps = num
                            UserDefaults.standard.set(num, forKey: "last_steps")
                            changed = true
                        }
                        break
                    }
                }
                if self.currentSteps == 0 {
                    for k in ["steps", "step", "step_count", "cur_steps", "sport_step"] {
                        if let num = dict[k] as? Int, num > 0 {
                            if self.currentSteps != num {
                                self.currentSteps = num
                                UserDefaults.standard.set(num, forKey: "last_steps")
                                changed = true
                            }
                            break
                        }
                    }
                }

                // Heart rate (Strictly real-time keys only; do NOT parse avg_hr, last_hr, silent_hr)
                var hrKeys = ["cur_hr", "heart_rateVal", "heartRateVal", "heart_rate", "heartRate", "bpm"]
                if type == .heartRate { hrKeys.append("value") }
                
                for k in hrKeys {
                    if let v = dict[k] {
                        let hrInt: Int? = (v as? Int) ?? (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) }
                        if let hr = hrInt, (40...220).contains(hr) {
                            self.updateLiveHeartRate(hr, source: "syncKey:\(k)")
                            break
                        }
                    }
                }

                // SpO2
                var spo2Keys = ["spo2", "blood_oxygen", "bloodOxygen", "o2"]
                if type == .bloodOxygen { spo2Keys.append("value") }
                
                for k in spo2Keys {
                    if let v = dict[k] {
                        let o2Int: Int? = (v as? Int) ?? (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) }
                        if let o2 = o2Int, (90...100).contains(o2) {
                            if self.currentSpo2 != o2 {
                                self.currentSpo2 = o2
                                UserDefaults.standard.set(o2, forKey: "last_spo2")
                                changed = true
                            }
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
                    if let num = item as? Int {
                        if (40...220).contains(num) && type == .heartRate {
                            self.updateLiveHeartRate(num, source: "syncArray")
                            break
                        } else if (90...100).contains(num) && (type == .bloodOxygen) {
                            if self.currentSpo2 != num {
                                self.currentSpo2 = num
                                UserDefaults.standard.set(num, forKey: "last_spo2")
                                changed = true
                            }
                            break
                        } else {
                            inspect(element: item)
                        }
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

    // MARK: - Direct Binary Health File Fallback (Initial connection only)
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
                    // Only use historical storage as a fallback when live reading has not arrived yet!
                    guard self.currentHeartRate == 0 else { continue }
                    if let data = try? Data(contentsOf: fileURL), data.count >= 2 {
                        let bytes = [UInt8](data)
                        let startIdx = ((bytes.count - 1) % 2 == 1) ? bytes.count - 1 : bytes.count - 2
                        if startIdx >= 1 {
                            for i in stride(from: startIdx, through: 1, by: -2) {
                                let hr = Int(bytes[i])
                                if (40...220).contains(hr) {
                                    DispatchQueue.main.async {
                                        if self.currentHeartRate == 0 {
                                            print("[IdoSmartManager] Found initial fallback HR in storage: \(hr) bpm")
                                            self.updateLiveHeartRate(hr, source: "storageFallback")
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                } else if fileURL.lastPathComponent == "v3_spo2" || fileURL.lastPathComponent == "v3_blood_oxygen" || fileURL.lastPathComponent == "spo2" {
                    // Prevent stale historical data from overwriting live UI. Only read if current is 0, OR if file was recently modified by sync
                    let modDate = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date ?? Date.distantPast
                    if self.currentSpo2 == 0 || Date().timeIntervalSince(modDate) < 30 {
                        if let data = try? Data(contentsOf: fileURL), data.count >= 2 {
                            let bytes = [UInt8](data)
                            let startIdx = ((bytes.count - 1) % 2 == 1) ? bytes.count - 1 : bytes.count - 2
                            if startIdx >= 1 {
                                for i in stride(from: startIdx, through: 1, by: -2) {
                                    let spo2 = Int(bytes[i])
                                    if (90...100).contains(spo2) {
                                        DispatchQueue.main.async {
                                            if self.currentSpo2 != spo2 {
                                                print("[IdoSmartManager] Found fresh SpO2 in storage: \(spo2)%")
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
    }

    private func startPeriodicSync() {
        periodicTimer?.cancel()
        periodicTimer = Timer.publish(every: 12, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                if self?.isConnected == true && self?.isActivated == true {
                    self?.requestLiveMetrics()
                    GoogleSheetSyncManager.shared.checkAndTriggerPeriodicSyncIfNeeded()
                }
            }
            
        healthSyncTimer?.cancel()
        healthSyncTimer = Timer.publish(every: 60, on: .main, in: .common)
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
        healthSyncTimer?.cancel()
        healthSyncTimer = nil
    }

    // MARK: - IDOBleDelegate Implementation
    func scanResult(list: [IDODeviceModel]?) {
        guard let list = list else { return }
        handleDiscoveredList(list)
    }

    func bluetoothState(state: IDOBluetoothStateModel) {
        print("[IdoSmartManager] Bluetooth state changed: \(state.type.rawValue)")
        DispatchQueue.main.async {
            if state.type == .poweredOn {
                if !self.isConnected {
                    self.scheduleReconnect(immediate: true)
                }
            } else if !self.isConnected {
                self.statusMessage = "البلوتوث غير مفعّل أو غير متاح. فعّل البلوتوث ليتصل السوار تلقائياً ⚠️"
            }
        }
    }

    func deviceState(state: IDODeviceStateModel) {
        print("[IdoSmartManager] Device state changed: state=\(state.state.rawValue), errorState=\(state.errorState.rawValue)")
        DispatchQueue.main.async {
            switch state.state {
            case .connected:
                self.isConnected = true
                self.isConnectAttemptActive = false
                self.userInitiatedDisconnect = false
                self.reconnectAttempt = 0
                self.connectTimeoutTimer?.invalidate()
                self.connectTimeoutTimer = nil
                self.autoReconnectTimer?.invalidate()
                self.autoReconnectTimer = nil
                // Connected: stop any background scan to save battery & avoid radio contention
                self.autoScanToken += 1
                if self.isScanning {
                    sdk.ble.stopScan()
                    self.isScanning = false
                }
                GoogleSheetSyncManager.shared.startAutoSyncTimer()

                if self.isBoundForCurrentDevice(fallbackMac: state.macAddress) {
                    self.statusMessage = "متصل بالسوار! بانتظار بروتوكول الاتصال... ⚡"
                    // Preferred trigger is protocolConnectCompleted; this is a fallback if it never arrives
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self = self, self.isConnected, !self.isActivated, !self.isBindingInProgress else { return }
                        self.activateWatch(force: true)
                    }
                } else {
                    self.statusMessage = "متصل بالبلوتوث! جاري طلب الاقتران... ⌚"
                    // Delay bind to ensure BLE stack is ready; avoids dropping bind command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        guard let self = self, self.isConnected, !self.isBindingInProgress else { return }
                        self.bindDeviceIfNeeded()
                    }
                }

            case .disconnected:
                self.isConnected = false
                self.isActivated = false
                self.isActivating = false
                self.isBindingInProgress = false
                self.isConnectAttemptActive = false
                self.isSyncingHealth = false
                self.activationToken += 1   // cancels any pending activation sequence
                self.connectTimeoutTimer?.invalidate()
                self.connectTimeoutTimer = nil
                self.stopPeriodicSync()
                GoogleSheetSyncManager.shared.stopAutoSyncTimer()

                if self.userInitiatedDisconnect {
                    self.statusMessage = "تم قطع الاتصال"
                } else {
                    self.statusMessage = "تم قطع الاتصال. جارٍ البحث التلقائي لإعادة الاتصال بالسوار فور رصده... 🔄"
                    self.scheduleReconnect(immediate: false)
                }

            case .connecting:
                self.statusMessage = "جاري الاتصال بالسوار والتحقق..."
                if self.connectTimeoutTimer == nil {
                    self.startConnectTimeout()
                }

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
            if (40...220).contains(hr) {
                print("[IdoSmartManager] LIVE HR STREAM from 07 40 packet: \(hr) bpm")
                self.updateLiveHeartRate(hr, source: "0x07 0x40 PPG stream")
            }
        } else if bytes[0] == 0x07 && (bytes[1] == 0x41 || bytes[1] == 0x42) {
            let spo2 = Int(bytes[2])
            if (90...100).contains(spo2) {
                print("[IdoSmartManager] LIVE SpO2 STREAM from 07 \(String(format: "%02x", bytes[1])): \(spo2)%")
                DispatchQueue.main.async {
                    self.lastLiveSpo2Time = Date()
                    if self.currentSpo2 != spo2 {
                        self.currentSpo2 = spo2
                        UserDefaults.standard.set(spo2, forKey: "last_spo2")
                        self.updateMetrics()
                    }
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
                if self.isBoundForCurrentDevice() {
                    self.statusMessage = "تم اكتمال بروتوكول الاتصال! جاري تنشيط الحساسات... ⚡"
                    self.activateWatch(force: true)
                } else {
                    // It will be activated after the binding process completes
                    self.statusMessage = "تم اكتمال بروتوكول الاتصال، بانتظار الاقتران... ⏳"
                    if !self.isBindingInProgress {
                        self.bindDeviceIfNeeded()
                    }
                }

            case .syncHealthDataCompleted:
                self.isSyncingHealth = false
                // Always read freshly synced metrics (e.g. manual SpO2 tests)
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
            let type = model.dataType?.intValue ?? 0
            #if DEBUG
            print("[IdoSmartManager] Device notification dataType=\(type) param=\(model.parameter?.intValue ?? -1)")
            #endif
            
            // Documented: 19 = Manual health measurement sync request
            // Triggers when a standalone sensor reading on the watch completes.
            if type == 19 {
                if !self.isSyncingHealth {
                    self.syncHealthData()
                }
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
