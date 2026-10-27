//
//  AppModelTests.swift
//  HellHoundsTests
//
//  Broker choice: launch arguments, Settings, and switching brokers.
//

import Foundation
import Testing
@testable import HellHounds

struct BrokerAddressTests {
    @Test(arguments: [
        ("localhost", "1883", BrokerAddress(host: "localhost", port: 1883)),
        ("  test.mosquitto.org ", " 8883 ", BrokerAddress(host: "test.mosquitto.org", port: 8883)),
        ("192.168.1.20", "1884", BrokerAddress(host: "192.168.1.20", port: 1884)),
        ("", "1883", nil),
        ("my broker", "1883", nil),
        ("mqtt://localhost", "1883", nil),
        ("user@host", "1883", nil),
        ("localhost", "0", nil),
        ("localhost", "65536", nil),
        ("localhost", "abc", nil),
    ] as [(String, String, BrokerAddress?)])
    func parsesSettingsInput(host: String, port: String, expected: BrokerAddress?) {
        #expect(BrokerAddress(host: host, portText: port) == expected)
    }

    @Test func launchArgumentsGiveHostAndOptionalPort() {
        #expect(BrokerAddress.fromLaunchArguments([:]) == nil)
        #expect(BrokerAddress.fromLaunchArguments(["mqttHost": "localhost"]) == BrokerAddress(host: "localhost", port: 1883))
        #expect(BrokerAddress.fromLaunchArguments(["mqttHost": "localhost", "mqttPort": "1884"]) == BrokerAddress(host: "localhost", port: 1884))
        #expect(BrokerAddress.fromLaunchArguments(["mqttHost": "localhost", "mqttPort": 1885]) == BrokerAddress(host: "localhost", port: 1885))
    }
}

@MainActor
struct AppModelTests {
    let defaults: UserDefaults
    /// Every broker a transport was made for, in order.
    final class Made { var brokers: [BrokerAddress] = []; var transports: [FakeMQTTTransport] = [] }
    let made = Made()

    init() {
        let suite = "AppModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeModel(launchArguments: [String: Any] = [:], usesFakeTransport: Bool = false) -> AppModel {
        AppModel(defaults: defaults, launchArguments: launchArguments, usesFakeTransport: usesFakeTransport) { [made] broker in
            made.brokers.append(broker)
            let fake = FakeMQTTTransport()
            made.transports.append(fake)
            return fake
        }
    }

    private let local = BrokerAddress(host: "localhost", port: 1883)!

    @Test func defaultsToThePublicBroker() {
        let model = makeModel()
        #expect(model.broker == .publicBroker)
        #expect(!model.isBrokerLocked)
        #expect(made.brokers == [.publicBroker])
    }

    @Test func usesTheStoredBroker() {
        local.store(in: defaults)
        #expect(makeModel().broker == local)
    }

    @Test func launchArgumentsWinAndLockTheBroker() {
        BrokerAddress(host: "stored.example", port: 1883)!.store(in: defaults)
        let model = makeModel(launchArguments: ["mqttHost": "localhost"])
        #expect(model.broker == local)
        #expect(model.isBrokerLocked)

        model.useBroker(.publicBroker)
        #expect(model.broker == local)
        #expect(made.brokers == [local])
        #expect(BrokerAddress.stored(in: defaults)?.host == "stored.example")
    }

    @Test func fakeTransportLocksTheBroker() {
        let model = makeModel(usesFakeTransport: true)
        #expect(model.isBrokerLocked)
        model.useBroker(local)
        #expect(made.brokers == [.publicBroker])
    }

    @Test func switchingSavesConnectsAndDropsTheOldConnection() async throws {
        let model = makeModel()
        let oldStore = model.store
        oldStore.connect()
        #expect(made.transports[0].isConnected)

        model.useBroker(local)

        #expect(model.broker == local)
        #expect(BrokerAddress.stored(in: defaults) == local)
        #expect(made.brokers == [.publicBroker, local])
        #expect(model.store !== oldStore)
        #expect(!made.transports[0].isConnected)
        #expect(made.transports[1].isConnected)
    }

    @Test func choosingTheSameBrokerChangesNothing() {
        let model = makeModel()
        let store = model.store
        model.useBroker(.publicBroker)
        #expect(model.store === store)
        #expect(made.brokers.count == 1)
        #expect(BrokerAddress.stored(in: defaults) == nil)
    }
}
