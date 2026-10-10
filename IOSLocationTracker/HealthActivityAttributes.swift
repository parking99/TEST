//
//  HealthActivityAttributes.swift
//  SecurityPass
//
//  بيانات النشاط المباشر (Live Activity) — مشتركة بين التطبيق وامتداد شاشة القفل،
//  فلا تُضِف هنا أي اعتماد على أنواع التطبيق.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct HealthActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var heartRate: Int
        public var spo2: Int
        public var statusMessage: String
        public var isCritical: Bool

        // البطاقة الطبية — يراها المسعف على شاشة القفل دون فتح الجوال.
        public var bloodType: String
        public var conditions: String
        public var allergies: String
        public var emergencyPhone: String

        public init(heartRate: Int, spo2: Int, statusMessage: String, isCritical: Bool,
                    bloodType: String = "", conditions: String = "", allergies: String = "",
                    emergencyPhone: String = "") {
            self.heartRate = heartRate
            self.spo2 = spo2
            self.statusMessage = statusMessage
            self.isCritical = isCritical
            self.bloodType = bloodType
            self.conditions = conditions
            self.allergies = allergies
            self.emergencyPhone = emergencyPhone
        }

        public var hasMedicalCard: Bool {
            !(bloodType.isEmpty && conditions.isEmpty && allergies.isEmpty && emergencyPhone.isEmpty)
        }
    }

    public var employeeID: String

    public init(employeeID: String) {
        self.employeeID = employeeID
    }
}
#endif
