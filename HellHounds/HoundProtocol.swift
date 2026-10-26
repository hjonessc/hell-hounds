//
//  HoundProtocol.swift
//  HellHounds
//
//  Topics and payloads from docs/PROTOCOL.md. Pure functions, no I/O.
//

import Foundation

enum HoundProtocol {
    static let topicPrefix = "HellHounds-MQTT"

    enum Leaf: String {
        case setState = "set-state"
        case setLevel = "set-level"
        case getStatus = "msg"
        case statusJSON = "status-json"
    }

    static func topic(_ leaf: Leaf, index: Int) -> String {
        "\(topicPrefix)/\(index)/\(leaf.rawValue)"
    }

    /// On the wire `"1"` is on and `"0"` is off.
    static func setStatePayload(isOn: Bool) -> String {
        isOn ? "1" : "0"
    }

    static func setLevelPayload(brightness: Int) -> String {
        String(min(max(brightness, 0), 100))
    }

    /// Any payload works; the hound ignores it.
    static let getStatusPayload = "0"

    /// The device index in `<prefix>/<index>/status-json`, or nil for any other topic.
    static func statusIndex(fromTopic topic: String) -> Int? {
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == topicPrefix,
              parts[2] == Leaf.statusJSON.rawValue
        else { return nil }
        return Int(parts[1])
    }
}

/// A decoded `status-json` payload. Missing `ledLvl` / `battery` come back as
/// nil (the old app crashed on these); a missing `ledState` means off.
struct HoundStatus: Equatable {
    var isOn: Bool
    var brightness: Int?
    var battery: Int?

    private struct Wire: Decodable {
        var ledState: Bool?
        var ledLvl: Int?
        var battery: Int?

        private enum CodingKeys: String, CodingKey {
            case ledState, ledLvl, battery
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // The real firmware sends `true`/`false`; the sim and PROTOCOL.md use 1/0.
            if let flag = try? container.decodeIfPresent(Bool.self, forKey: .ledState) {
                ledState = flag
            } else {
                ledState = try container.decodeIfPresent(Int.self, forKey: .ledState).map { $0 == 1 }
            }
            ledLvl = try container.decodeIfPresent(Int.self, forKey: .ledLvl)
            battery = try container.decodeIfPresent(Int.self, forKey: .battery)
        }
    }

    /// Accepts plain JSON and the backslash-escaped JSON the firmware seems to send.
    init?(payload: String) {
        let unescaped = payload.replacingOccurrences(of: "\\", with: "")
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(unescaped.utf8)) else {
            return nil
        }
        isOn = wire.ledState ?? false
        brightness = wire.ledLvl
        battery = wire.battery
    }

    init(isOn: Bool, brightness: Int?, battery: Int?) {
        self.isOn = isOn
        self.brightness = brightness
        self.battery = battery
    }
}
