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
        /// Hound → app, text: charge, voltage, current (seen from a real hound).
        case batStats = "BatStats"
    }

    static func topic(_ leaf: Leaf, index: Int) -> String {
        "\(topicPrefix)/\(index)/\(leaf.rawValue)"
    }

    /// Matches `leaf` for every index, for discovery.
    static func topicFilter(_ leaf: Leaf) -> String {
        "\(topicPrefix)/+/\(leaf.rawValue)"
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
        index(fromTopic: topic, leaf: .statusJSON)
    }

    /// The device index in `<prefix>/<index>/<leaf>`, or nil for any other topic.
    /// The index must be plain digits: anyone on the broker can publish here,
    /// and `Int("+1")` or `Int("-1")` would otherwise parse.
    static func index(fromTopic topic: String, leaf: Leaf) -> Int? {
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == topicPrefix,
              parts[2] == leaf.rawValue,
              !parts[1].isEmpty,
              parts[1].allSatisfy({ ("0"..."9").contains($0) })
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

/// A decoded `BatStats` payload, such as ` SOC: 90 %\n4.00 V | -79 mA\nTime: 155.45`.
/// Each value is nil when its part is missing; nil overall if none is there.
struct BatteryStats: Equatable {
    var charge: Int?
    var voltage: Double?
    /// Negative while discharging.
    var milliamps: Int?

    init?(payload: String) {
        func match(_ pattern: Regex<(Substring, Substring)>) -> Substring? {
            payload.firstMatch(of: pattern)?.output.1
        }
        charge = match(/SOC:\s*(\d+)\s*%/).flatMap { Int($0) }
        voltage = match(/(\d+(?:\.\d+)?)\s*V\b/).flatMap { Double($0) }
        milliamps = match(/(-?\d+)\s*mA/).flatMap { Int($0) }
        if charge == nil && voltage == nil && milliamps == nil { return nil }
    }

    init(charge: Int?, voltage: Double?, milliamps: Int?) {
        self.charge = charge
        self.voltage = voltage
        self.milliamps = milliamps
    }
}
