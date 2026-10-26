//
//  HoundStoreTests.swift
//  HellHoundsTests
//
//  The status / set-state / set-level round trip through HoundStore and the
//  in-app fake transport.
//

import Testing
@testable import HellHounds

@MainActor
struct HoundStoreTests {
    let fake = FakeMQTTTransport()
    let store: HoundStore

    init() {
        store = HoundStore(transport: fake, statusPollDelay: .zero)
    }

    /// Waits for the store to process transport events asynchronously.
    private func eventually(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private func connectAndWaitForAllHounds() async throws {
        store.connect()
        try #require(try await eventually { store.hounds.allSatisfy(\.isConnected) })
    }

    // MARK: - Status

    @Test func connectSubscribesToEachHoundAndPollsIt() async throws {
        try await connectAndWaitForAllHounds()

        #expect(store.connectionState == .connected)
        #expect(fake.subscriptions == Set((0..<4).map { HoundProtocol.topic(.statusJSON, index: $0) }))
        #expect(fake.published.map(\.topic) == (0..<4).map { HoundProtocol.topic(.getStatus, index: $0) })
        #expect(store.hounds.map(\.battery) == [100, 70, 40, 10])
        #expect(store.hounds.map(\.brightness) == [50, 50, 50, 50])
        #expect(store.hounds.allSatisfy { !$0.isOn })
    }

    @Test func houndsStayDisconnectedUntilTheyReport() async throws {
        fake.hounds = [2: .init(battery: 33)]
        store.connect()
        #expect(try await eventually { store.hounds[2].isConnected })
        #expect(store.hounds[2].battery == 33)
        #expect(store.hounds.filter(\.isConnected).count == 1)
    }

    @Test func unknownIndicesAndMalformedStatusAreIgnored() async throws {
        try await connectAndWaitForAllHounds()
        fake.subscribe(to: "HellHounds-MQTT/+/status-json")

        fake.deliver(MQTTMessage(topic: "HellHounds-MQTT/7/status-json", payload: #"{"ledState":true,"ledLvl":1,"battery":1}"#))
        fake.deliver(MQTTMessage(topic: HoundProtocol.topic(.statusJSON, index: 0), payload: "garbage"))
        fake.deliver(MQTTMessage(topic: HoundProtocol.topic(.statusJSON, index: 1), payload: #"{"ledState":true,"ledLvl":77,"battery":70}"#))

        #expect(try await eventually { store.hounds[1].isOn })
        #expect(store.hounds.count == 4)
        #expect(store.hounds[0] == Hound(index: 0, isConnected: true, isOn: false, brightness: 50, battery: 100))
    }

    @Test func missingFieldsKeepThePreviousValues() async throws {
        try await connectAndWaitForAllHounds()
        fake.deliver(MQTTMessage(topic: HoundProtocol.topic(.statusJSON, index: 3), payload: #"{"ledState":true}"#))
        #expect(try await eventually { store.hounds[3].isOn })
        #expect(store.hounds[3].brightness == 50)
        #expect(store.hounds[3].battery == 10)
    }

    // MARK: - Commands

    @Test func setOnRoundTrip() async throws {
        try await connectAndWaitForAllHounds()

        store.setOn(true, houndIndex: 1)
        #expect(fake.published.last == MQTTMessage(topic: "HellHounds-MQTT/1/set-state", payload: "1"))
        #expect(try await eventually { store.hounds[1].isOn })
        #expect(fake.hounds[1]?.isOn == true)

        store.setOn(false, houndIndex: 1)
        #expect(fake.published.last == MQTTMessage(topic: "HellHounds-MQTT/1/set-state", payload: "0"))
        #expect(try await eventually { !store.hounds[1].isOn })
    }

    @Test func setBrightnessRoundTrip() async throws {
        try await connectAndWaitForAllHounds()

        store.setBrightness(42, houndIndex: 2)
        #expect(fake.published.last == MQTTMessage(topic: "HellHounds-MQTT/2/set-level", payload: "42"))
        #expect(try await eventually { store.hounds[2].brightness == 42 })
        #expect(!store.hounds[2].isOn)  // the level doesn't switch the LED on

        store.setBrightness(150, houndIndex: 2)
        #expect(fake.published.last?.payload == "100")
        #expect(try await eventually { store.hounds[2].brightness == 100 })
    }

    @Test func masterCommandsGoToEveryHound() async throws {
        try await connectAndWaitForAllHounds()
        let before = fake.published.count

        store.setAllOn(true)
        store.setAllBrightness(30)

        #expect(Array(fake.published.dropFirst(before)) ==
            (0..<4).map { MQTTMessage(topic: HoundProtocol.topic(.setState, index: $0), payload: "1") } +
            (0..<4).map { MQTTMessage(topic: HoundProtocol.topic(.setLevel, index: $0), payload: "30") })
        #expect(try await eventually { store.hounds.allSatisfy { $0.isOn && $0.brightness == 30 } })
    }

    @Test func pollOnlyHoundsDontUpdateAfterCommands() async throws {
        fake.reportsStatusAfterCommands = false
        try await connectAndWaitForAllHounds()

        store.setOn(true, houndIndex: 0)
        #expect(fake.hounds[0]?.isOn == true)
        fake.hounds[1]?.battery = 69
        fake.sendStatus(index: 1)  // a later message, to know the store has caught up
        #expect(try await eventually { store.hounds[1].battery == 69 })
        #expect(!store.hounds[0].isOn)
    }

    // MARK: - Master and connection

    @Test func masterSummarisesConnectedHounds() async throws {
        fake.hounds = [
            0: .init(isOn: false, level: 20, battery: 80),
            1: .init(isOn: true, level: 90, battery: 55),
            2: .init(isOn: false, level: 40, battery: 30),
        ]
        store.connect()
        #expect(try await eventually { store.hounds.filter(\.isConnected).count == 3 })

        #expect(store.master == Hound(index: -1, isConnected: true, isOn: true, brightness: 90, battery: 30))
    }

    @Test func masterIsDisconnectedWithNoHounds() {
        #expect(store.master == Hound(index: -1, isConnected: false, isOn: false, brightness: 0, battery: 0))
    }

    @Test func dropMarksEveryHoundDisconnectedAndReconnectRepolls() async throws {
        try await connectAndWaitForAllHounds()
        store.setOn(true, houndIndex: 0)
        #expect(try await eventually { store.hounds[0].isOn })

        fake.dropConnection()
        #expect(try await eventually { store.connectionState == .disconnected })
        #expect(store.hounds.allSatisfy { !$0.isConnected })
        #expect(store.hounds[0].isOn)  // last known values are kept
        #expect(fake.subscriptions.isEmpty)

        let before = fake.published.count
        store.connect()
        #expect(try await eventually { store.hounds.allSatisfy(\.isConnected) })
        #expect(fake.subscriptions.count == 4)
        #expect(fake.published.dropFirst(before).map(\.topic) == (0..<4).map { HoundProtocol.topic(.getStatus, index: $0) })
    }

    @Test func connectWhileConnectedDoesNothing() async throws {
        try await connectAndWaitForAllHounds()
        let before = fake.published.count
        store.connect()
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.connectionState == .connected)
        #expect(fake.published.count == before)
    }
}
