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
    private(set) var hounds: [Hound]

    @ObservationIgnored private let transport: any MQTTTransport
    @ObservationIgnored private let statusPollDelay: Duration
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Indices 0..<houndCount until discovery lands (Phase 3).
    init(transport: any MQTTTransport, houndCount: Int = 4, statusPollDelay: Duration = .milliseconds(200)) {
        self.transport = transport
        self.statusPollDelay = statusPollDelay
        hounds = (0..<houndCount).map { Hound(index: $0) }
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
                for hound in hounds {
                    transport.subscribe(to: HoundProtocol.topic(.statusJSON, index: hound.index))
                }
                pollTask?.cancel()
                pollTask = Task { [weak self, statusPollDelay] in
                    try? await Task.sleep(for: statusPollDelay)
                    guard !Task.isCancelled else { return }
                    self?.pollStatus()
                }
            case .disconnected:
                pollTask?.cancel()
                for i in hounds.indices {
                    hounds[i].isConnected = false
                }
            case .connecting:
                break
            }
        case .message(let message):
            guard let index = HoundProtocol.statusIndex(fromTopic: message.topic),
                  let i = hounds.firstIndex(where: { $0.index == index }),
                  let status = HoundStatus(payload: message.payload)
            else { return }
            hounds[i].isConnected = true
            hounds[i].isOn = status.isOn
            if let brightness = status.brightness { hounds[i].brightness = brightness }
            if let battery = status.battery { hounds[i].battery = battery }
        }
    }

    private func pollStatus() {
        for hound in hounds {
            transport.publish(HoundProtocol.getStatusPayload, to: HoundProtocol.topic(.getStatus, index: hound.index))
        }
    }
}
