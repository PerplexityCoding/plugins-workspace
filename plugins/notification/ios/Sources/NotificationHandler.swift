// Copyright 2019-2023 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import Tauri
import UserNotifications

public class NotificationHandler: NSObject, NotificationHandlerProtocol {

  public weak var plugin: Plugin?

  private var notificationsMap = [String: Notification]()

  internal func saveNotification(_ key: String, _ notification: Notification) {
    notificationsMap.updateValue(notification, forKey: key)
  }

  public func requestPermissions(with completion: ((Bool, Error?) -> Void)? = nil) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.badge, .alert, .sound]) { (granted, error) in
      completion?(granted, error)
    }
  }

  public func checkPermissions(with completion: ((UNAuthorizationStatus) -> Void)? = nil) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      completion?(settings.authorizationStatus)
    }
  }

  public func willPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
    let notificationData = toActiveNotification(notification.request)
    try? self.plugin?.trigger("notification", data: notificationData)

    if let options = notificationsMap[notification.request.identifier] {
      if options.silent ?? false {
        return UNNotificationPresentationOptions.init(rawValue: 0)
      }
    }

    return [
      .badge,
      .sound,
      .alert,
    ]
  }

  public func didReceive(response: UNNotificationResponse) {
    let originalNotificationRequest = response.notification.request
    let actionId = response.actionIdentifier

    var actionIdValue: String
    // We turn the two default actions (open/dismiss) into generic strings
    if actionId == UNNotificationDefaultActionIdentifier {
      actionIdValue = "tap"
    } else if actionId == UNNotificationDismissActionIdentifier {
      actionIdValue = "dismiss"
    } else {
      actionIdValue = actionId
    }

    var inputValue: String? = nil
    // If the type of action was for an input type, get the value
    if let inputType = response as? UNTextInputNotificationResponse {
      inputValue = inputType.userText
    }

    try? self.plugin?.trigger(
      "actionPerformed",
      data: ReceivedNotification(
        actionId: actionIdValue,
        inputValue: inputValue,
        notification: toActiveNotification(originalNotificationRequest)
      ))
  }

  func toActiveNotification(_ request: UNNotificationRequest) -> ActiveNotification {
    let notificationRequest = notificationsMap[request.identifier]

    let extra = request.content.userInfo["__EXTRA__"] as? [String: String] ?? notificationRequest?.extra
    let scheduleDict = request.content.userInfo["__SCHEDULE__"] as? [String: Any]

    return ActiveNotification(
      id: Int(request.identifier) ?? -1,
      title: request.content.title,
      body: request.content.body,
      sound: notificationRequest?.sound ?? "",
      actionTypeId: request.content.categoryIdentifier,
      attachments: notificationRequest?.attachments,
      extra: extra,
      schedule: parseSchedule(scheduleDict)
    )
  }

  func toPendingNotification(_ request: UNNotificationRequest) -> PendingNotification {
    let notificationRequest = notificationsMap[request.identifier]

    let extra = request.content.userInfo["__EXTRA__"] as? [String: String] ?? notificationRequest?.extra
    let scheduleDict = request.content.userInfo["__SCHEDULE__"] as? [String: Any]

    return PendingNotification(
      id: Int(request.identifier) ?? -1,
      title: request.content.title,
      body: request.content.body,
      extra: extra,
      schedule: parseSchedule(scheduleDict)
    )
  }
}

struct PendingNotification: Encodable {
  let id: Int
  let title: String
  let body: String
  let extra: [String: String]?
  let schedule: ScheduleResponse?
}

struct ActiveNotification: Encodable {
  let id: Int
  let title: String
  let body: String
  let sound: String
  let actionTypeId: String
  let attachments: [NotificationAttachment]?
  let extra: [String: String]?
  let schedule: ScheduleResponse?
}

struct ReceivedNotification: Encodable {
  let actionId: String
  let inputValue: String?
  let notification: ActiveNotification
}

struct ScheduleResponse: Encodable {
  struct At: Encodable {
    let date: String
    let repeating: Bool
  }
  struct Interval: Encodable {
    let year: Int?
    let month: Int?
    let day: Int?
    let weekday: Int?
    let hour: Int?
    let minute: Int?
    let second: Int?
  }
  struct Every: Encodable {
    let interval: String
    let count: Int
  }

  let at: At?
  let interval: Interval?
  let every: Every?
}

func parseSchedule(_ dict: [String: Any]?) -> ScheduleResponse? {
  guard let dict = dict, let type = dict["type"] as? String else { return nil }

  switch type {
  case "at":
    if let date = dict["date"] as? String, let repeating = dict["repeating"] as? Bool {
      return ScheduleResponse(at: .init(date: date, repeating: repeating), interval: nil, every: nil)
    }
  case "interval":
    if let intervalDict = dict["interval"] as? [String: Any] {
      let interval = ScheduleResponse.Interval(
        year: intervalDict["year"] as? Int,
        month: intervalDict["month"] as? Int,
        day: intervalDict["day"] as? Int,
        weekday: intervalDict["weekday"] as? Int,
        hour: intervalDict["hour"] as? Int,
        minute: intervalDict["minute"] as? Int,
        second: intervalDict["second"] as? Int
      )
      return ScheduleResponse(at: nil, interval: interval, every: nil)
    }
  case "every":
    if let interval = dict["interval"] as? String, let count = dict["count"] as? Int {
      return ScheduleResponse(at: nil, interval: nil, every: .init(interval: interval, count: count))
    }
  default:
    return nil
  }
  return nil
}