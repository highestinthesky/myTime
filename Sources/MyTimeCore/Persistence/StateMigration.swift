import Foundation

/// Transforms authenticated 0.1.0 payloads before decoding the current model (§5.11).
enum StateMigration {
    private static let removedKeys: Set<String> = [
        "quickLookSecondsPerToken", "quickLookMaxTokens", "replyTokenCost", "replySeconds", "replyPerDay",
    ]

    static func migrateV1(_ json: inout [String: Any]) {
        var notice =
            "Quick look and Reply mode are now Unlock. Choose 1, 2, 5, or 10 minutes at the gate, 1 token a minute. "
            + "An Unlock bought less than 15 minutes after the last one costs twice as much."
        var appNames: [String: String] = [:]
        if var settings = json["settings"] as? [String: Any] {
            if var apps = settings["apps"] as? [[String: Any]] {
                for index in apps.indices {
                    let app = apps[index]
                    if let id = app["id"] as? String, let name = app["name"] as? String {
                        appNames[id.lowercased()] = name
                    }
                    guard let modes = app["modes"] as? [String] else { continue }
                    let hasUnlock = modes.contains("quickLook") || modes.contains("unlock")
                    var migratedModes: [String] = hasUnlock ? ["unlock"] : []
                    if modes.contains("booked") {
                        migratedModes.append("booked")
                    }
                    apps[index]["modes"] = migratedModes
                    if modes.contains("reply") && !hasUnlock, let name = app["name"] as? String {
                        notice += " Unlock is off for \(name) because Quick look was off."
                    }
                }
                settings["apps"] = apps
            }
            if var numbers = settings["numbers"] as? [String: Any] {
                for key in removedKeys {
                    numbers.removeValue(forKey: key)
                }
                settings["numbers"] = numbers
            }
            json["settings"] = settings
        }

        var dropped = 0
        if let pending = json["pending"] as? [[String: Any]] {
            json["pending"] = pending.compactMap { original -> [String: Any]? in
                guard var change = original["change"] as? [String: Any] else { return original }
                var item = original
                if var mode = change["setMode"] as? [String: Any] {
                    if mode["mode"] as? String == "reply" {
                        dropped += 1
                        return nil
                    }
                    if mode["mode"] as? String == "quickLook" {
                        mode["mode"] = "unlock"
                        change["setMode"] = mode
                        item["change"] = change
                        if let id = mode["appID"] as? String, let name = appNames[id.lowercased()] {
                            item["summary"] = "Turn on Unlock for \(name)"
                        }
                    }
                }
                if let number = change["setNumber"] as? [String: Any],
                    let key = number["key"] as? String, removedKeys.contains(key)
                {
                    dropped += 1
                    return nil
                }
                return item
            }
        }
        if dropped == 1 {
            notice += " A pending Quick look or Reply mode change was canceled."
        } else if dropped > 1 {
            notice += " \(dropped) pending Quick look or Reply mode changes were canceled."
        }

        if var daily = json["daily"] as? [String: [String: Any]] {
            for key in daily.keys {
                daily[key]?.removeValue(forKey: "quickLooks")
                daily[key]?.removeValue(forKey: "replies")
            }
            json["daily"] = daily
        }
        json.removeValue(forKey: "unlock")
        json.removeValue(forKey: "unlockStreak")
        json["schemaVersion"] = 2
        json["migrationNotice"] = notice
    }
}
