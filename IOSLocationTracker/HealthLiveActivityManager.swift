//
//  HealthLiveActivityManager.swift
//  SecurityPass
//
//  يدير الإشعارات التنبيهية المحلية (Local Notifications) والإشعار العريض المستمر (Live Activity)
//

import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
import UserNotifications

// MARK: - البيانات المشتركة مع الويدجت (Live Activity)

#if canImport(ActivityKit)
@available(iOS 16.1, *)
public struct HealthActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var heartRate: Int
        public var spo2: Int
        public var statusMessage: String
        public var isCritical: Bool
        
        public init(heartRate: Int, spo2: Int, statusMessage: String, isCritical: Bool) {
            self.heartRate = heartRate
            self.spo2 = spo2
            self.statusMessage = statusMessage
            self.isCritical = isCritical
        }
    }

    public var employeeID: String
    
    public init(employeeID: String) {
        self.employeeID = employeeID
    }
}
#endif

// MARK: - المدير الرئيسي للإشعارات المستمرة

public final class HealthLiveActivityManager {
    public static let shared = HealthLiveActivityManager()
    private init() {}
    
    public func start(employeeID: String, heartRate: Int, spo2: Int) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            
            // إنهاء أي نشاط سابق لنفس العامل
            endAll()
            
            let attributes = HealthActivityAttributes(employeeID: employeeID)
            let state = HealthActivityAttributes.ContentState(
                heartRate: heartRate,
                spo2: spo2,
                statusMessage: "قيد المراقبة المستمرة",
                isCritical: false
            )
            
            do {
                _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
                print("[LiveActivity] Started successfully")
            } catch {
                print("[LiveActivity] Error starting: \(error.localizedDescription)")
            }
        }
        #endif
    }
    
    public func update(heartRate: Int, spo2: Int, isCritical: Bool, message: String) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            Task {
                for activity in Activity<HealthActivityAttributes>.activities {
                    let newState = HealthActivityAttributes.ContentState(
                        heartRate: heartRate,
                        spo2: spo2,
                        statusMessage: message,
                        isCritical: isCritical
                    )
                    await activity.update(using: newState)
                }
            }
        }
        #endif
    }
    
    public func endAll() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            Task {
                for activity in Activity<HealthActivityAttributes>.activities {
                    await activity.end(dismissalPolicy: .immediate)
                }
            }
        }
        #endif
    }
}
