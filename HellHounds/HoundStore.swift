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

    @ObservationIgnored private let transport: any MQTTTransport
    @ObservationIgnored private let probeIndices: Range<Int>
    @ObservationIgnored private let statusPollDelay: Duration
    @ObservationIgnored private let answerTimeout: Duration
    /// Set by `suspend()`: the coming disconnect keeps every hound's last state.
    @ObservationIgnored private var keepsHoundsOnDisconnect = false
    @ObservationIgnored private var reportedSinceConnect: Set<Int> = []
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Hounds are discovered: any index that publishes `status-json` is added.
    /// Hounds that only answer polls (Q2) are found by polling `probeIndices`
    /// on every connect, along with every index already known. A hound that
    /// hasn't reported `answerTimeout` after the poll is offline.
    init(
        transport: any MQTTTransport,
        probeIndices: Range<Int> = 0..<8,
        statusPollDelay: Duration = .milliseconds(200),
        answerTimeout: Duration = .seconds(3)
    ) {
        self.transport = transport
        self.probeIndices = probeIndices
        self.statusPollDelay = statusPollDelay
        self.answerTimeout = answerTimeout
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

    func setOn(_ isOn: Bool, houndIndex: Int) {
        transport.publish(HoundProtocol.setStatePayload(isOn: isOn), to: HoundProtocol.topic(.setState, index: houndIndex))
    }

    func setBrightness(_ brightness: Int, houndIndex: Int) {
        transport.publish(HoundProtocol.setLevelPayload(brightness: brightness), to: HoundProtocol.topic(.setLevel, index: houndIndex))
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
            connectionState = state
            switch state {
            case .connected:
                transport.subscribe(to: HoundProtocol.topicFilter(.statusJSON))
                reportedSinceConnect = []
                isDiscovering = true
                pollTask?.cancel()
                pollTask = Task { [weak self, statusPollDelay, answerTimeout] in
                    do {
                        try await Task.sleep(for: statusPollDelay)
                        try Task.checkCancellation()
                        self?.pollStatus()
                        try await Task.sleep(for: answerTimeout)
                    } catch {
                        return  // disconnected or reconnected meanwhile
                    }
                    self?.markUnansweredHoundsOffline()
                }
            case .disconnected:
                pollTask?.cancel()
                isDiscovering = false
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
            guard let index = HoundProtocol.statusIndex(fromTopic: message.topic),
                  let status = HoundStatus(payload: message.payload)
            else { return }
            let i = houndPosition(index: index)
            reportedSinceConnect.insert(index)
            hounds[i].isConnected = true
            hounds[i].isOn = status.isOn
            if let brightness = status.brightness { hounds[i].brightness = brightness }
            if let battery = status.battery { hounds[i].battery = battery }
        }
    }

    /// The position of hound `index` in `hounds`, inserting it in index order if new.
    private func houndPosition(index: Int) -> Int {
        let i = hounds.firstIndex(where: { $0.index >= index }) ?? hounds.endIndex
        if i == hounds.endIndex || hounds[i].index != index {
            hounds.insert(Hound(index: index), at: i)
        }
        return i
    }

    private func markUnansweredHoundsOffline() {
        for i in hounds.indices where !reportedSinceConnect.contains(hounds[i].index) {
            hounds[i].isConnected = false
        }
        isDiscovering = false
    }

    private func pollStatus() {
        let indices = Set(probeIndices).union(hounds.map(\.index)).sorted()
        for index in indices {
            transport.publish(HoundProtocol.getStatusPayload, to: HoundProtocol.topic(.getStatus, index: index))
        }
    }
}
