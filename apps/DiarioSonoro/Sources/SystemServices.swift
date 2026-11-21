import Foundation
import UIKit
import UserNotifications
import LocalAuthentication
import BackgroundTasks
import SonoroCore

/// Local notifications: evening soundtrack and "un anno fa oggi".
///
/// Notifications carry fixed text, so they are rescheduled with fresh
/// content every time the diary changes.
enum Notifier {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static func reschedule(data: DiaryData, today: DayDate, minuteNow: Int) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter {
                $0.hasPrefix(NotificationPlanner.soundtrackPrefix) || $0.hasPrefix(NotificationPlanner.anniversaryPrefix)
                    || $0.hasPrefix(NotificationPlanner.reminderPrefix)
            }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            var planned: [PlannedNotification] = []
            let s = data.settings
            if s.soundtrackNotification, minuteNow < s.soundtrackTime.minutes,
               let n = NotificationPlanner.soundtrack(day: today, clips: data.clips, time: s.soundtrackTime) {
                planned.append(n)
            }
            if s.reminderEnabled {
                let recordedToday = data.clips.contains { $0.day == today }
                planned += NotificationPlanner.reminders(from: today, days: 14, start: s.reminderStart, end: s.reminderEnd,
                                                         minuteNow: minuteNow, skipToday: s.reminderSkipIfRecorded && recordedToday)
            }
            if s.anniversaryNotification {
                planned += NotificationPlanner.anniversaries(from: today, days: 30, clips: data.clips,
                                                             time: s.anniversaryTime, minuteNow: minuteNow)
            }
            // iOS keeps at most 64 pending notifications per app.
            for n in planned.prefix(60) {
                let content = UNMutableNotificationContent()
                content.title = n.title
                content.body = n.body
                content.sound = .default
                content.userInfo = ["link": n.link.url.absoluteString]
                var when = DateComponents()
                when.year = n.day.year
                when.month = n.day.month
                when.day = n.day.day
                when.hour = n.time.hour
                when.minute = n.time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
                center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
            }
        }
    }
}

/// Face ID / passcode.
enum DeviceAuth {
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "codice"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Best-effort evening build: iOS decides when the task runs. The
/// soundtrack is in any case built as soon as the app is opened after the
/// configured time, and when the notification is tapped.
enum BackgroundBuilder {
    static let identifier = "com.garoth93.diariosonoro.soundtrack"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let work = Task { @MainActor in
                await AppModel.shared.buildDueSoundtracks()
                schedule(time: AppModel.shared.data.settings.soundtrackTime)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule(time: ClockTime) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = SoundtrackScheduler.nextRun(after: Date(), time: time).addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Short haptics at the start / end of a recording.
@MainActor
enum Haptics {
    static func start() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func end() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tick() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
}
