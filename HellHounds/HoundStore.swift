//
//  HoundStore.swift
//  HellHounds
//
//  The app's state: the connection and every hound, driven by an MQTTTransport.
//

import Foundation
import Observation

struct Hound: Identifiable, Equatable {
    let index: Int
    /// Reported since the last connect, or before a `suspend()` and not yet
    /// found missing: the values below are the last ones it reported.
    var isConnected = false
    var isOn = false
    var brightness = 0
    var battery = 0
    /// When its last message came in, since launch.
    var lastHeard: Date?
    /// Its last `status-json`, as received.
    var lastStatusPayload: String?
    /// From its last `BatStats` message.
    var batteryStats: BatteryStats?
    var messagesSent = 0
    var messagesReceived = 0

    var id: Int { index }
}

@MainActor
@Observable
final class HoundStore {
    private(set) var connectionState: MQTTConnectionState = .disconnected
    /// Every hound that has reported since launch, sorted by index.
    private(set) var hounds: [Hound] = []
    /// From connecting until hounds that didn't answer the poll are marked offline.
    private(set) var isDiscovering = false
    /// When the connection to the broker was last made, and last lost.
    private(set) var connectedAt: Date?
    private(set) var disconnectedAt: Date?
    /// Hounds blinking so they can be found; see `toggleIdentify(houndIndex:)`.
    private(set) var identifying: Set<Int> = []

    @ObservationIgnored private let transport: any MQTTTransport
    @ObservationIgnored private let probeIndices: Range<Int>
    @ObservationIgnored private let statusPollDelay: Duration
    @ObservationIgnored private let answerTimeout: Duration
    @ObservationIgnored private let identifyDuration: Duration
    @ObservationIgnored private let identifyBlink: Duration
    @ObservationIgnored private let log: EventLog
    @ObservationIgnored private let now: () -> Date
    /// Set by `suspend()`: the coming disconnect keeps every hound's last state.
    @ObservationIgnored private var keepsHoundsOnDisconnect = false
    @ObservationIgnored private var reportedSinceConnect: Set<Int> = []
    /// Messages sent to indices no hound has reported from yet (polls).
    @ObservationIgnored private var sentBeforeFound: [Int: Int] = [:]
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var identifyTasks: [Int: Task<Void, Never>] = [:]
    /// Each identifying hound's state before it started blinking.
    @ObservationIgnored private var stateBeforeIdentify: [Int: (isOn: Bool, brightness: Int)] = [:]

    /// Hounds are discovered: any index that publishes `status-json` is added.
    /// Hounds that only answer polls (Q2) are found by polling `probeIndices`
    /// on every connect, along with every index already known. A hound that
    /// hasn't reported `answerTimeout` after the poll is offline.
    init(
        transport: any MQTTTransport,
        log: EventLog = EventLog(),
        probeIndices: Range<Int> = 0..<8,
        statusPollDelay: Duration = .milliseconds(200),
        answerTimeout: Duration = .seconds(3),
        identifyDuration: Duration = .seconds(30),
        identifyBlink: Duration = .milliseconds(500),
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.log = log
        self.probeIndices = probeIndices
        self.statusPollDelay = statusPollDelay
        self.answerTimeout = answerTimeout
        self.identifyDuration = identifyDuration
        self.identifyBlink = identifyBlink
        self.now = now
        // Ends when the transport (owned by this store) finishes its stream.
        eventsTask = Task { [weak self, events = transport.events] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    /// Summary of the connected hounds: on if any is on, the highest
    /// brightness and the lowest battery.
    var master: Hound {
        let connected = hounds.filter(\.isConnected)
        return Hound(
            index: -1,
            isConnected: !connected.isEmpty,
            isOn: connected.contains(where: \.isOn),
            brightness: connected.map(\.brightness).max() ?? 0,
            battery: connected.map(\.battery).min() ?? 0
        )
    }

    // MARK: - Commands

    func connect() {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting
        transport.connect()
    }

    func disconnect() {
        transport.disconnect()
    }

    /// Disconnects for a while (the app is in the background) but keeps
    /// showing every hound as it last was. After the next connect, hounds
    /// that don't answer the poll go offline.
    func suspend() {
        keepsHoundsOnDisconnect = connectionState == .connected
        transport.disconnect()
    }

    /// Connects if needed, or asks every hound for its status again. Returns
    /// once every hound known before has answered, or the answer time is up.
    func refresh() async {
        let expected = Set(hounds.map(\.index))
        switch connectionState {
        case .disconnected:
            log.add(.app, "Refresh: connecting")
            connect()
        case .connected:
            log.add(.app, "Refresh: asking every hound for its status")
            startDiscovery(pollDelay: .zero)
        case .connecting:
            break
        }
        let deadline = ContinuousClock.now + statusPollDelay + answerTimeout + .seconds(2)
        while ContinuousClock.now < deadline {
            if connectionState == .connected {
                if !isDiscovering { return }
                if !expected.isEmpty && reportedSinceConnect.isSuperset(of: expected) { return }
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
    }

    /// A command from the user; it stops the hound identifying, and wins.
    func setOn(_ isOn: Bool, houndIndex: Int) {
        stopIdentifying(houndIndex: houndIndex, restoring: false)
        send(.setState, HoundProtocol.setStatePayload(isOn: isOn), to: houndIndex, note: isOn ? "Switch on" : "Switch off")
    }

    func setBrightness(_ brightness: Int, houndIndex: Int) {
        stopIdentifying(houndIndex: houndIndex, restoring: false)
        let payload = HoundProtocol.setLevelPayload(brightness: brightness)
        send(.setLevel, payload, to: houndIndex, note: "Brightness \(payload) %")
    }

    // MARK: - Identify

    /// Starts hound `houndIndex` blinking for `identifyDuration`, or stops it
    /// early. Afterwards it goes back to how it was. Works with the current
    /// firmware: it's only `set-state` on and off (and `set-level` 100 if it
    /// was dim, so the blinking shows).
    func toggleIdentify(houndIndex: Int) {
        if identifying.contains(houndIndex) {
            log.add(.app, "Identify stopped", houndIndex: houndIndex)
            stopIdentifying(houndIndex: houndIndex, restoring: true)
        } else {
            startIdentifying(houndIndex: houndIndex)
        }
    }

    private func startIdentifying(houndIndex index: Int) {
        guard connectionState == .connected,
              let hound = hounds.first(where: { $0.index == index }), hound.isConnected
        else { return }
        identifying.insert(index)
        stateBeforeIdentify[index] = (hound.isOn, hound.brightness)
        log.add(.app, "Identify: blinking for \(identifyDuration.components.seconds) s", houndIndex: index)
        if hound.brightness < 50 {
            send(.setLevel, HoundProtocol.setLevelPayload(brightness: 100), to: index)
        }
        identifyTasks[index] = Task { [weak self, identifyDuration, identifyBlink] in
            let end = ContinuousClock.now + identifyDuration
            var lit = !hound.isOn
            while ContinuousClock.now < end && !Task.isCancelled {
                self?.send(.setState, HoundProtocol.setStatePayload(isOn: lit), to: index)
                lit.toggle()
                do {
                    try await Task.sleep(for: identifyBlink)
                } catch {
                    return  // stopped
                }
            }
            self?.log.add(.app, "Identify finished", houndIndex: index)
            self?.stopIdentifying(houndIndex: index, restoring: true)
        }
    }

    /// Restoring sends the old state twice: messages go at most once, and a
    /// hound left blinking-off would look broken.
    private func stopIdentifying(houndIndex index: Int, restoring: Bool) {
        guard identifying.remove(index) != nil else { return }
        identifyTasks.removeValue(forKey: index)?.cancel()
        guard let before = stateBeforeIdentify.removeValue(forKey: index), restoring else { return }
        let state = HoundProtocol.setStatePayload(isOn: before.isOn)
        send(.setLevel, HoundProtocol.setLevelPayload(brightness: before.brightness), to: index)
        send(.setState, state, to: index, note: "Back to \(before.isOn ? "on" : "off"), \(before.brightness) %")
        Task { [weak self, identifyBlink] in
            try? await Task.sleep(for: identifyBlink)
            guard let self, !self.identifying.contains(index) else { return }
            self.send(.setState, state, to: index)
        }
    }

    /// Publishes to hound `index`; logs it when there's a `note`.
    private func send(_ leaf: HoundProtocol.Leaf, _ payload: String, to index: Int, note: String? = nil) {
        transport.publish(payload, to: HoundProtocol.topic(leaf, index: index))
        if let i = hounds.firstIndex(where: { $0.index == index }) {
            hounds[i].messagesSent += 1
        } else {
            sentBeforeFound[index, default: 0] += 1
        }
        if let note {
            log.add(.sent, "\(note) (\(leaf.rawValue) \(payload))", houndIndex: index)
        }
    }

    func setAllOn(_ isOn: Bool) {
        for hound in hounds {
            setOn(isOn, houndIndex: hound.index)
        }
    }

    func setAllBrightness(_ brightness: Int) {
        for hound in hounds {
            setBrightness(brightness, houndIndex: hound.index)
        }
    }

    // MARK: - Transport events

    private func handle(_ event: MQTTTransportEvent) {
        switch event {
        case .stateChanged(let state):
            let previous = connectionState
            connectionState = state
            switch state {
            case .connected:
                connectedAt = now()
                log.add(.connection, "Connected to the broker")
                transport.subscribe(to: HoundProtocol.topicFilter(.statusJSON))
                transport.subscribe(to: HoundProtocol.topicFilter(.batStats))
                startDiscovery(pollDelay: statusPollDelay)
            case .disconnected:
                if previous == .connected {
                    disconnectedAt = now()
                    log.add(.connection, keepsHoundsOnDisconnect ? "Disconnected (in the background)" : "Disconnected")
                }
                pollTask?.cancel()
                isDiscovering = false
                for index in identifying {
                    stopIdentifying(houndIndex: index, restoring: false)
                }
                if keepsHoundsOnDisconnect {
                    keepsHoundsOnDisconnect = false
                } else {
                    for i in hounds.indices {
                        hounds[i].isConnected = false
                    }
                }
            case .connecting:
                break
            }
        case .message(let message):
            if let index = HoundProtocol.index(fromTopic: message.topic, leaf: .batStats) {
                guard let i = hounds.firstIndex(where: { $0.index == index }),
                      let stats = BatteryStats(payload: message.payload)
                else { return }
                hounds[i].batteryStats = stats
                hounds[i].lastHeard = now()
                hounds[i].messagesReceived += 1
                return
            }
            guard let index = HoundProtocol.statusIndex(fromTopic: message.topic) else { return }
            guard let status = HoundStatus(payload: message.payload) else {
                log.add(.warning, "Ignored a status it couldn't read: \(message.payload.prefix(80))", houndIndex: index)
                return
            }
            let isNew = !hounds.contains(where: { $0.index == index })
            let i = houndPosition(index: index)
            let wasConnected = hounds[i].isConnected
            reportedSinceConnect.insert(index)
            hounds[i].isConnected = true
            hounds[i].isOn = status.isOn
            if let brightness = status.brightness { hounds[i].brightness = brightness }
            if let battery = status.battery { hounds[i].battery = battery }
            hounds[i].lastHeard = now()
            hounds[i].lastStatusPayload = message.payload
            hounds[i].messagesReceived += 1
            let summary = "\(status.isOn ? "on" : "off"), \(hounds[i].brightness) %, battery \(hounds[i].battery) %"
            if isNew {
                log.add(.found, "Found: \(summary)", houndIndex: index)
            } else if !wasConnected {
                log.add(.found, "Back online: \(summary)", houndIndex: index)
            } else if !identifying.contains(index) {  // blinking would flood the log
                log.add(.received, "Status: \(summary)", houndIndex: index)
            }
        case .failed(let reason):
            log.add(.warning, reason)
        }
    }

    /// Polls every hound, then marks those that don't answer offline.
    private func startDiscovery(pollDelay: Duration) {
        reportedSinceConnect = []
        isDiscovering = true
        pollTask?.cancel()
        pollTask = Task { [weak self, answerTimeout] in
            do {
                try await Task.sleep(for: pollDelay)
                try Task.checkCancellation()
                self?.pollStatus()
                try await Task.sleep(for: answerTimeout)
            } catch {
                return  // disconnected or reconnected meanwhile
            }
            self?.markUnansweredHoundsOffline()
        }
    }

    /// The position of hound `index` in `hounds`, inserting it in index order if new.
    private func houndPosition(index: Int) -> Int {
        let i = hounds.firstIndex(where: { $0.index >= index }) ?? hounds.endIndex
        if i == hounds.endIndex || hounds[i].index != index {
            var hound = Hound(index: index)
            hound.messagesSent = sentBeforeFound.removeValue(forKey: index) ?? 0
            hounds.insert(hound, at: i)
        }
        return i
    }

    private func markUnansweredHoundsOffline() {
        for i in hounds.indices where !reportedSinceConnect.contains(hounds[i].index) {
            if hounds[i].isConnected {
                log.add(.warning, "Didn't answer; now offline", houndIndex: hounds[i].index)
            }
            hounds[i].isConnected = false
        }
        isDiscovering = false
    }

    private func pollStatus() {
        let indices = Set(probeIndices).union(hounds.map(\.index)).sorted()
        for index in indices {
            send(.getStatus, HoundProtocol.getStatusPayload, to: index)
        }
        log.add(.sent, "Asked hounds \(indices.map { String($0 + 1) }.joined(separator: ", ")) for their status")
    }
}
