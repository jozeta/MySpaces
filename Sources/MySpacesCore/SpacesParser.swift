import Foundation

/// Parses the "Monitors" structure shared by CGSCopyManagedDisplaySpaces and the
/// com.apple.spaces preferences domain.
public enum SpacesParser {
    public static func parse(monitors: [[String: Any]]) -> [Space] {
        var result: [Space] = []
        for monitor in monitors {
            let displayID = monitor["Display Identifier"] as? String ?? "Main"
            let currentID = (monitor["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            for raw in monitor["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = raw["ManagedSpaceID"] as? Int else { continue }
                let kind: Space.Kind
                switch raw["type"] as? Int ?? 0 {
                case 0: kind = .desktop
                case 4: kind = .fullscreen(appName: fullscreenAppName(raw))
                default: continue
                }
                result.append(Space(
                    managedID: id,
                    uuid: raw["uuid"] as? String ?? "",
                    displayID: displayID,
                    kind: kind,
                    isCurrent: id == currentID
                ))
            }
        }
        return result
    }

    public static func parse(spacesPreferences prefs: [String: Any]) -> [Space] {
        let config = prefs["SpacesDisplayConfiguration"] as? [String: Any]
        let management = config?["Management Data"] as? [String: Any]
        return parse(monitors: management?["Monitors"] as? [[String: Any]] ?? [])
    }

    static func fullscreenAppName(_ raw: [String: Any]) -> String {
        let tiles = (raw["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
        let names = tiles.compactMap { $0["appName"] as? String }
        return names.isEmpty ? "Full-screen app" : names.joined(separator: " & ")
    }
}
