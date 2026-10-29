//
//  AppModel.swift
//  HellHounds
//
//  Owns the broker choice and the HoundStore for it. Changing the broker
//  replaces the store: hounds on another broker are other hounds. Also
//  keeps the connection for a short while in the background, so a quick
//  app switch doesn't reconnect.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppModel {
    private(set) var broker: BrokerAddress
    private(set) var store: HoundStore
    /// The broker comes from `-mqttHost` (or the fake transport is on), so
    /// Settings can't change it. Keeps test runs off the public broker.
    let isBrokerLocked: Bool
    let usesFakeTransport: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeTransport: @MainActor (BrokerAddress) -> any MQTTTransport
    @ObservationIgnored private let backgroundGrace: Duration
    @ObservationIgnored private let beginBackgroundTime: BeginBackgroundTime
    @ObservationIgnored private var graceTask: Task<Void, Never>?
    @ObservationIgnored private var endBackgroundTime: (@MainActor () -> Void)?

    /// Asks iOS for time to keep running in the background; returns the call
    /// that hands it back. `expired` runs if iOS wants it back first.
    typealias BeginBackgroundTime = @MainActor (_ expired: @escaping @MainActor () -> Void) -> @MainActor () -> Void

    init(
        defaults: UserDefaults = .standard,
        launchArguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
        usesFakeTransport: Bool = TransportFactory.usesFakeTransport,
        makeTransport: @escaping @MainActor (BrokerAddress) -> any MQTTTransport = TransportFactory.makeTransport(broker:),
        backgroundGrace: Duration = .seconds(25),
        beginBackgroundTime: @escaping BeginBackgroundTime = AppModel.beginApplicationBackgroundTask
    ) {
        self.defaults = defaults
        self.makeTransport = makeTransport
        self.backgroundGrace = backgroundGrace
        self.beginBackgroundTime = beginBackgroundTime
        self.usesFakeTransport = usesFakeTransport
        let launchBroker = BrokerAddress.fromLaunchArguments(launchArguments)
        isBrokerLocked = usesFakeTransport || launchBroker != nil
        let broker = launchBroker ?? BrokerAddress.stored(in: defaults) ?? .publicBroker
        self.broker = broker
        store = HoundStore(transport: makeTransport(broker))
    }

    /// Which hound profiles (names and looks) belong to this broker.
    var profileBrokerKey: String {
        HoundProfile.brokerKey(for: broker, usesFakeTransport: usesFakeTransport)
    }

    /// Saves `newBroker` and connects to it, dropping the current connection.
    func useBroker(_ newBroker: BrokerAddress) {
        guard !isBrokerLocked, newBroker != broker else { return }
        newBroker.store(in: defaults)
        broker = newBroker
        store.disconnect()
        store = HoundStore(transport: makeTransport(newBroker))
        store.connect()
    }

    // MARK: - Background

    /// Stays connected for `backgroundGrace` (iOS allows about 30 s), then
    /// suspends the store, which keeps showing the hounds as they were.
    func enterBackground() {
        guard graceTask == nil else { return }
        endBackgroundTime = beginBackgroundTime { [weak self] in self?.endGrace(suspending: true) }
        graceTask = Task { [weak self, backgroundGrace] in
            do {
                try await Task.sleep(for: backgroundGrace)
            } catch {
                return  // back in the foreground
            }
            self?.endGrace(suspending: true)
        }
    }

    /// Connects, unless the connection outlived the time in the background.
    func enterForeground() {
        endGrace(suspending: false)
        store.connect()
    }

    private func endGrace(suspending: Bool) {
        guard let graceTask else { return }
        graceTask.cancel()
        self.graceTask = nil
        if suspending { store.suspend() }
        endBackgroundTime?()
        endBackgroundTime = nil
    }

    static func beginApplicationBackgroundTask(expired: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let id = UIApplication.shared.beginBackgroundTask(withName: "MQTT grace period") {
            MainActor.assumeIsolated { expired() }
        }
        return { UIApplication.shared.endBackgroundTask(id) }
    }
}
