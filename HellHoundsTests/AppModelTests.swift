//
//  AppModelTests.swift
//  HellHoundsTests
//
//  Broker choice: launch arguments, Settings, and switching brokers; the
//  grace period in the background.
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
    /// Background time asked of the fake iOS: how often, how often handed back,
    /// and the latest expiry handler.
    final class BackgroundTime { var begun = 0; var ended = 0; var expire: (@MainActor () -> Void)? }
    let backgroundTime = BackgroundTime()

    init() {
        let suite = "AppModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeModel(
        launchArguments: [String: Any] = [:],
        usesFakeTransport: Bool = false,
        backgroundGrace: Duration = .seconds(10)
    ) -> AppModel {
        AppModel(
            defaults: defaults,
            launchArguments: launchArguments,
            usesFakeTransport: usesFakeTransport,
            makeTransport: { [made] broker in
                made.brokers.append(broker)
                let fake = FakeMQTTTransport()
                made.transports.append(fake)
                return fake
            },
            backgroundGrace: backgroundGrace,
            beginBackgroundTime: { [backgroundTime] expired in
                backgroundTime.begun += 1
                backgroundTime.expire = expired
                return { backgroundTime.ended += 1 }
            }
        )
    }

    private func eventually(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private func connectedModel(backgroundGrace: Duration = .seconds(10)) async throws -> AppModel {
        let model = makeModel(backgroundGrace: backgroundGrace)
        model.enterForeground()
        try #require(try await eventually { model.store.hounds.count == 4 && model.store.hounds.allSatisfy(\.isConnected) })
        return model
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

    // MARK: - Background

    @Test func aQuickTripToTheBackgroundKeepsTheConnection() async throws {
        let model = try await connectedModel()
        let polls = made.transports[0].published.count

        model.enterBackground()
        try await Task.sleep(for: .milliseconds(50))
        model.enterForeground()

        #expect(made.transports[0].isConnected)
        #expect(model.store.connectionState == .connected)
        #expect(made.transports[0].published.count == polls, "no reconnect, so no new poll")
        #expect(backgroundTime.begun == 1)
        #expect(backgroundTime.ended == 1)
    }

    @Test func afterTheGracePeriodTheStoreSuspendsAndKeepsTheHounds() async throws {
        let model = try await connectedModel(backgroundGrace: .milliseconds(50))

        model.enterBackground()
        #expect(try await eventually { model.store.connectionState == .disconnected })
        #expect(!made.transports[0].isConnected)
        #expect(model.store.hounds.allSatisfy { $0.isConnected }, "the last state still shows")
        #expect(backgroundTime.ended == 1)

        model.enterForeground()
        #expect(try await eventually { model.store.connectionState == .connected })
        #expect(backgroundTime.ended == 1, "nothing more to hand back")
    }

    @Test func iOSTakingTheTimeBackSuspendsEarly() async throws {
        let model = try await connectedModel()

        model.enterBackground()
        try #require(backgroundTime.expire != nil)
        backgroundTime.expire?()

        #expect(try await eventually { model.store.connectionState == .disconnected })
        #expect(backgroundTime.ended == 1)
    }
}
