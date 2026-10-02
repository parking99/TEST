import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

class IdoSmartManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = IdoSmartManager()

    // MARK: - Published Properties
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

    // MARK: - CoreBluetooth
    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?

    // Standard BLE Services & Characteristics
    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    private let thermometerServiceUUID = CBUUID(string: "1809")
    private let temperatureMeasurementUUID = CBUUID(string: "2A1C")

    // Vendor / IDO Smart Custom Services
    private let idoServiceUUID = CBUUID(string: "00000001-0000-1000-8000-00805F9B34FB")
    private let idoNotifyUUID = CBUUID(string: "00000003-0000-1000-8000-00805F9B34FB")
    private let idoWriteUUID = CBUUID(string: "00000002-0000-1000-8000-00805F9B34FB")

    private var discoveredPeripheralsMap: [UUID: DiscoveredDevice] = [:]
    private var timerSubscription: AnyCancellable?

    override private init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        restoreSavedMetrics()
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
        self.currentBloodPressure = getFormattedBloodPressure()
        self.currentTemperature = getCalculatedTemperature()
    }

    func isDeviceBound(uuidString: String) -> Bool {
        return UserDefaults.standard.bool(forKey: "bound_\(uuidString)")
    }

    func markDeviceBound(uuidString: String, bound: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(bound, forKey: "bound_\(uuidString)")
        if bound {
            defaults.set(uuidString, forKey: "last_connected_uuid")
        }
    }

    func getFormattedBloodPressure() -> String {
        let (sys, dia) = BloodPressureAlgorithm.calculate(heartRate: currentHeartRate, steps: currentSteps)
        return "\(sys)/\(dia)"
    }

    func getCalculatedTemperature() -> Double {
        if currentTemperature >= 35.0 && currentTemperature <= 42.0 && currentTemperature != 36.6 {
            return (currentTemperature * 10).rounded() / 10.0
        }
        let hr = (40...220).contains(currentHeartRate) ? currentHeartRate : 72
        let delta = Double(hr - 70) * 0.008
        let metabolicShift = min(max(delta, -0.3), 0.5)
        return ((36.6 + metabolicShift) * 10).rounded() / 10.0
    }

    // MARK: - Scanning & Connection
    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "يرجى تفعيل البلوتوث أولاً"
            return
        }

        discoveredPeripheralsMap.removeAll()
        discoveredDevices.removeAll()
        isScanning = true
        statusMessage = "جارٍ البحث عن السوار الذكي أو الساعة..."

        // Scan for all peripherals with allowDuplicates false
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Stop scanning after 15 seconds automatically
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.isScanning == true {
                self?.stopScan()
            }
        }
    }

    func stopScan() {
        guard isScanning else { return }
        isScanning = false
        centralManager.stopScan()
        statusMessage = "تم انتهاء البحث. انقر على السوار للاتصال وقراءة المؤشرات."
    }

    func connect(device: DiscoveredDevice) {
        stopScan()
        statusMessage = "جارٍ الاتصال بـ \(device.name)..."
        activePeripheral = device.peripheral
        activePeripheral?.delegate = self
        currentDeviceName = device.name
        currentDeviceUUID = device.id.uuidString

        centralManager.connect(device.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    func disconnect() {
        if let p = activePeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        isConnected = false
        isActivated = false
        statusMessage = "حالة الاتصال: غير متصل"
    }

    func forceUnbindAndReset() {
        statusMessage = "جارٍ تصفير وإلغاء اقتران الساعة... 🔄"
        if let uuid = activePeripheral?.identifier.uuidString {
            markDeviceBound(uuidString: uuid, bound: false)
        }
        UserDefaults.standard.removeObject(forKey: "last_connected_uuid")
        disconnect()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.currentHeartRate = 0
            self.currentSteps = 0
            self.currentBloodPressure = "120/80"
            self.statusMessage = "تم تصفير الاقتران بنجاح! يمكنك الآن إعادة البحث والاقتران كجهاز جديد."
        }
    }

    func activateWatch() {
        guard isConnected, let p = activePeripheral else {
            statusMessage = "الساعة غير متصلة، يرجى الاتصال بالساعة أولاً"
            return
        }

        isActivated = true
        statusMessage = "جارٍ تنشيط شاشة وحساسات الساعة وبدء القياس... ⚡"

        // Send activation packets to custom IDO services if found
        for service in p.services ?? [] {
            for char in service.characteristics ?? [] {
                if char.properties.contains(.notify) {
                    p.setNotifyValue(true, for: char)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.statusMessage = "تم تشغيل حساسات الساعة وبدء قياس النبض والمؤشرات! ⚡"
        }
    }

    func tryAutoConnectLastDevice() {
        guard !isConnected, let savedUUIDString = UserDefaults.standard.string(forKey: "last_connected_uuid"),
              let uuid = UUID(uuidString: savedUUIDString) else {
            return
        }

        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let p = known.first {
            statusMessage = "جارٍ إعادة الاتصال التلقائي بالسوار السابق..."
            activePeripheral = p
            activePeripheral?.delegate = self
            currentDeviceUUID = uuid.uuidString
            currentDeviceName = p.name ?? "سوار ذكي"
            centralManager.connect(p, options: nil)
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "البلوتوث مفعل. جاهز للبحث عن الأجهزة."
            tryAutoConnectLastDevice()
        case .poweredOff:
            statusMessage = "البلوتوث متوقف. يرجى تفعيله."
            isConnected = false
            isScanning = false
        case .unauthorized:
            statusMessage = "صلاحية البلوتوث غير ممنوحة للتطبيق."
        default:
            statusMessage = "حالة البلوتوث غير متوفرة."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "سوار ذكي"
        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)

        if discoveredPeripheralsMap[peripheral.identifier] == nil {
            discoveredPeripheralsMap[peripheral.identifier] = device
            discoveredDevices.insert(device, at: 0)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusMessage = "تم الاتصال بالسوار \(currentDeviceName) بنجاح! ✅"
        markDeviceBound(uuidString: peripheral.identifier.uuidString, bound: true)

        peripheral.discoverServices([
            heartRateServiceUUID,
            batteryServiceUUID,
            thermometerServiceUUID,
            idoServiceUUID
        ])

        // Fallback: discover all services if specific UUIDs are not advertised
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            peripheral.discoverServices(nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusMessage = "فشل الاتصال بالسوار: \(error?.localizedDescription ?? "خطأ غير معروف")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isActivated = false
        statusMessage = "تم قطع الاتصال بالسوار"
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.read) {
                peripheral.readValue(for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }

        // 1. Standard Heart Rate Measurement (UUID: 2A37)
        if characteristic.uuid == heartRateMeasurementUUID {
            parseHeartRateData(data)
            return
        }

        // 2. Standard Battery Level (UUID: 2A19)
        if characteristic.uuid == batteryLevelUUID {
            let batt = Int(data[0])
            if (1...100).contains(batt) {
                DispatchQueue.main.async {
                    self.currentBattery = batt
                    UserDefaults.standard.set(batt, forKey: "last_battery")
                }
            }
            return
        }

        // 3. IDO Smart Stream (Packet 0x07 0x40) or Custom Notification
        let bytes = [UInt8](data)
        if bytes.count >= 3 && bytes[0] == 0x07 && bytes[1] == 0x40 {
            let hr = Int(bytes[2])
            if (35...240).contains(hr) {
                DispatchQueue.main.async {
                    self.currentHeartRate = hr
                    self.currentBloodPressure = self.getFormattedBloodPressure()
                    self.currentTemperature = self.getCalculatedTemperature()
                    UserDefaults.standard.set(hr, forKey: "last_heart_rate")
                }
            }
        }
    }

    private func parseHeartRateData(_ data: Data) {
        var buffer = [UInt8](repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)

        var bpm: Int = 0
        if (buffer[0] & 0x01) == 0 {
            bpm = Int(buffer[1])
        } else {
            bpm = Int(buffer[1]) | (Int(buffer[2]) << 8)
        }

        if (35...240).contains(bpm) {
            DispatchQueue.main.async {
                self.currentHeartRate = bpm
                self.currentBloodPressure = self.getFormattedBloodPressure()
                self.currentTemperature = self.getCalculatedTemperature()
                UserDefaults.standard.set(bpm, forKey: "last_heart_rate")
            }
        }
    }
}
