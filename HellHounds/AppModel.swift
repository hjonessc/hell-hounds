//
//  AppModel.swift
//  HellHounds
//
//  Owns the broker choice and the HoundStore for it. Changing the broker
//  replaces the store: hounds on another broker are other hounds.
//

import Foundation
import Observation

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

    init(
        defaults: UserDefaults = .standard,
        launchArguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
        usesFakeTransport: Bool = TransportFactory.usesFakeTransport,
        makeTransport: @escaping @MainActor (BrokerAddress) -> any MQTTTransport = TransportFactory.makeTransport(broker:)
    ) {
        self.defaults = defaults
        self.makeTransport = makeTransport
        self.usesFakeTransport = usesFakeTransport
        let launchBroker = BrokerAddress.fromLaunchArguments(launchArguments)
        isBrokerLocked = usesFakeTransport || launchBroker != nil
        let broker = launchBroker ?? BrokerAddress.stored(in: defaults) ?? .publicBroker
        self.broker = broker
        store = HoundStore(transport: makeTransport(broker))
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
}
