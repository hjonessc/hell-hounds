//
//  FakeMQTTTransport.swift
//  HellHounds
//
//  An in-process broker plus hounds, for unit tests, UI tests and screenshots
//  (ADR 0001). Speaks docs/PROTOCOL.md the way the real firmware does: plain
//  JSON with a boolean `ledState`, sent after a poll and after every command,
//  followed by a `BatStats` text message.
//

import Foundation

@MainActor
final class FakeMQTTTransport: MQTTTransport {
    struct FakeHound: Equatable {
        var isOn = false
        var level = 50
        var battery = 100
    }

    let events: AsyncStream<MQTTTransportEvent>
    private let continuation: AsyncStream<MQTTTransportEvent>.Continuation

    /// The simulated hounds by index. Change freely; nothing is sent until a
    /// command or `sendStatus(index:)`.
    var hounds: [Int: FakeHound]
    /// When false, hounds answer only `msg` polls (one possible answer to Q2).
    var reportsStatusAfterCommands = true

    private(set) var isConnected = false
    private(set) var subscriptions: Set<String> = []
    /// Everything the app published, in order.
    private(set) var published: [MQTTMessage] = []

    init(hounds: [Int: FakeHound] = FakeMQTTTransport.defaultHounds) {
        self.hounds = hounds
        (events, continuation) = AsyncStream.makeStream()
    }

    /// Four hounds with the batteries `hound-sim` uses.
    static let defaultHounds = hounds(count: 4)

    /// Hounds 0..<count, with batteries spread from 100 down to 10 like `hound-sim`.
    static func hounds(count: Int) -> [Int: FakeHound] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            let battery = count <= 1 ? 100 : Int((100 - 90 * Double(index) / Double(count - 1)).rounded(.toNearestOrEven))
            return (index, FakeHound(battery: battery))
        })
    }

    deinit {
        continuation.finish()
    }

    // MARK: - MQTTTransport

    func connect() {
        guard !isConnected else { return }
        continuation.yield(.stateChanged(.connecting))
        isConnected = true
        continuation.yield(.stateChanged(.connected))
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        subscriptions = []
        continuation.yield(.stateChanged(.disconnected))
    }

    func subscribe(to topicFilter: String) {
        guard isConnected else { return }
        subscriptions.insert(topicFilter)
    }

    func publish(_ payload: String, to topic: String) {
        guard isConnected else { return }
        published.append(MQTTMessage(topic: topic, payload: payload))

        let parts = topic.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == HoundProtocol.topicPrefix,
              let index = Int(parts[1]),
              hounds[index] != nil,
              let leaf = HoundProtocol.Leaf(rawValue: String(parts[2]))
        else { return }

        switch leaf {
        case .getStatus:
            sendStatus(index: index)
        case .setState:
            hounds[index]?.isOn = payload == "1"
            if reportsStatusAfterCommands { sendStatus(index: index) }
        case .setLevel:
            if let level = Int(payload) { hounds[index]?.level = level }
            if reportsStatusAfterCommands { sendStatus(index: index) }
        case .statusJSON, .batStats:
            break
        }
    }

    // MARK: - Test controls

    /// Publishes hound `index`'s status and battery stats, as the device would.
    func sendStatus(index: Int) {
        guard let hound = hounds[index] else { return }
        deliver(MQTTMessage(
            topic: HoundProtocol.topic(.statusJSON, index: index),
            payload: #"{"ledState":\#(hound.isOn),"ledLvl":\#(hound.level),"battery":\#(hound.battery)}"#
        ))
        let volts = 3.3 + 0.9 * Double(hound.battery) / 100
        let milliamps = hound.isOn ? -(20 + 3 * hound.level) : -79
        deliver(MQTTMessage(
            topic: HoundProtocol.topic(.batStats, index: index),
            payload: " SOC: \(hound.battery) %\n\(volts.formatted(.number.precision(.fractionLength(2)))) V | \(milliamps) mA\nTime: 155.45"
        ))
    }

    /// Delivers any message as if another client had published it.
    func deliver(_ message: MQTTMessage) {
        guard isConnected, subscriptions.contains(where: { Self.topic(message.topic, matches: $0) }) else { return }
        continuation.yield(.message(message))
    }

    /// Simulates the broker dropping the connection.
    func dropConnection() {
        disconnect()
    }

    /// MQTT topic filter matching with `+` and `#`.
    nonisolated static func topic(_ topic: String, matches filter: String) -> Bool {
        let name = topic.split(separator: "/", omittingEmptySubsequences: false)
        let levels = filter.split(separator: "/", omittingEmptySubsequences: false)
        for (i, level) in levels.enumerated() {
            if level == "#" { return true }
            guard i < name.count else { return false }
            if level != "+" && level != name[i] { return false }
        }
        return name.count == levels.count
    }
}
