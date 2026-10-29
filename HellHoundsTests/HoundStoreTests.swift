//
//  HoundStoreTests.swift
//  HellHoundsTests
//
//  Discovery and the status / set-state / set-level round trip through
//  HoundStore and the in-app fake transport.
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

    private func connectAndWaitForAllHounds(count: Int = 4) async throws {
        store.connect()
        try #require(try await eventually { store.hounds.count == count && store.hounds.allSatisfy(\.isConnected) })
    }

    private func status(index: Int, _ payload: String) -> MQTTMessage {
        MQTTMessage(topic: HoundProtocol.topic(.statusJSON, index: index), payload: payload)
    }

    private var probeTopics: [String] {
        (0..<8).map { HoundProtocol.topic(.getStatus, index: $0) }
    }

    // MARK: - Discovery

    @Test func noHoundsBeforeAnyReport() {
        #expect(store.hounds.isEmpty)
    }

    @Test func connectSubscribesToTheWildcardAndPollsTheProbeRange() async throws {
        try await connectAndWaitForAllHounds()
        #expect(store.connectionState == .connected)
        #expect(fake.subscriptions == ["HellHounds-MQTT/+/status-json"])
        #expect(fake.published.map(\.topic) == probeTopics)
        #expect(store.hounds.map(\.index) == [0, 1, 2, 3])
        #expect(store.hounds.map(\.battery) == [100, 70, 40, 10])
        #expect(store.hounds.map(\.brightness) == [50, 50, 50, 50])
        #expect(store.hounds.allSatisfy { !$0.isOn })
    }

    @Test func onlyHoundsThatReportAppear() async throws {
        fake.hounds = [2: .init(battery: 33), 5: .init(battery: 44)]
        store.connect()
        #expect(try await eventually { store.hounds.count == 2 })
        #expect(store.hounds.map(\.index) == [2, 5])
        #expect(store.hounds.map(\.battery) == [33, 44])
        #expect(store.hounds.allSatisfy { $0.isConnected })
    }

    @Test func sixHoundsAreDiscovered() async throws {
        fake.hounds = FakeMQTTTransport.hounds(count: 6)
        try await connectAndWaitForAllHounds(count: 6)
        #expect(store.hounds.map(\.index) == Array(0..<6))
        #expect(store.hounds.map(\.battery) == [100, 82, 64, 46, 28, 10])
    }

    @Test func houndsAreKeptInIndexOrder() async throws {
        fake.hounds = [:]
        store.connect()
        #expect(try await eventually { store.connectionState == .connected })
        for index in [6, 1, 9, 4] {
            fake.deliver(status(index: index, #"{"ledState":false}"#))
        }
        #expect(try await eventually { store.hounds.count == 4 })
        #expect(store.hounds.map(\.index) == [1, 4, 6, 9])
    }

    @Test func aHoundOutsideTheProbeRangeIsAddedWhenItReportsAndPolledAfterThat() async throws {
        try await connectAndWaitForAllHounds()
        fake.hounds[12] = .init(isOn: true, level: 5, battery: 60)
        fake.sendStatus(index: 12)  // reporting on its own, unasked
        #expect(try await eventually { store.hounds.count == 5 })
        #expect(store.hounds.last == Hound(index: 12, isConnected: true, isOn: true, brightness: 5, battery: 60))

        fake.dropConnection()
        #expect(try await eventually { store.connectionState == .disconnected })
        let before = fake.published.count
        store.connect()
        #expect(try await eventually { store.hounds.allSatisfy(\.isConnected) })
        #expect(fake.published.dropFirst(before).map(\.topic) == probeTopics + [HoundProtocol.topic(.getStatus, index: 12)])
    }

    @Test(arguments: [
        MQTTMessage(topic: "HellHounds-MQTT/x/status-json", payload: #"{"ledState":true}"#),
        MQTTMessage(topic: "HellHounds-MQTT//status-json", payload: #"{"ledState":true}"#),
        MQTTMessage(topic: "HellHounds-MQTT/-1/status-json", payload: #"{"ledState":true}"#),
        MQTTMessage(topic: "HellHounds-MQTT/+1/status-json", payload: #"{"ledState":true}"#),
        MQTTMessage(topic: "HellHounds-MQTT/7/status-json", payload: "garbage"),
    ])
    func malformedReportsAddNoHound(message: MQTTMessage) async throws {
        try await connectAndWaitForAllHounds()
        fake.deliver(message)
        fake.hounds[3]?.battery = 9
        fake.sendStatus(index: 3)  // a later message, to know the store has caught up
        #expect(try await eventually { store.hounds[3].battery == 9 })
        #expect(store.hounds.map(\.index) == [0, 1, 2, 3])
    }

    // MARK: - Status

    @Test func malformedStatusForAKnownHoundIsIgnored() async throws {
        try await connectAndWaitForAllHounds()
        fake.deliver(status(index: 0, "garbage"))
        fake.deliver(status(index: 1, #"{"ledState":true,"ledLvl":77,"battery":70}"#))

        #expect(try await eventually { store.hounds[1].isOn })
        #expect(store.hounds[0] == Hound(index: 0, isConnected: true, isOn: false, brightness: 50, battery: 100))
    }

    @Test func missingFieldsKeepThePreviousValues() async throws {
        try await connectAndWaitForAllHounds()
        fake.deliver(status(index: 3, #"{"ledState":true}"#))
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

    @Test func masterCommandsGoToEveryDiscoveredHound() async throws {
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
        #expect(fake.subscriptions.count == 1)
        #expect(fake.published.dropFirst(before).map(\.topic) == probeTopics)
    }

    @Test func connectWhileConnectedDoesNothing() async throws {
        try await connectAndWaitForAllHounds()
        let before = fake.published.count
        store.connect()
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.connectionState == .connected)
        #expect(fake.published.count == before)
    }

    // MARK: - Suspending (the app in the background)

    @Test func suspendKeepsEveryHoundsLastState() async throws {
        try await connectAndWaitForAllHounds()
        store.setOn(true, houndIndex: 0)
        #expect(try await eventually { store.hounds[0].isOn })

        store.suspend()
        #expect(try await eventually { store.connectionState == .disconnected })
        #expect(!fake.isConnected)
        #expect(store.hounds.allSatisfy { $0.isConnected })
        #expect(store.hounds[0].isOn)
    }

    @Test func aHoundThatDoesntAnswerAfterResumingGoesOffline() async throws {
        // Its own fake: two stores on one transport would split its events.
        let fake = FakeMQTTTransport()
        let store = HoundStore(transport: fake, statusPollDelay: .zero, answerTimeout: .milliseconds(100))
        store.connect()
        try #require(try await eventually { store.hounds.count == 4 && !store.isDiscovering })
        store.suspend()
        try #require(try await eventually { store.connectionState == .disconnected })

        fake.hounds[3] = nil  // switched off while the app was away
        store.connect()
        #expect(try await eventually { store.isDiscovering })
        #expect(store.hounds[3].isConnected, "still the last state while waiting for answers")
        #expect(try await eventually { !store.isDiscovering })
        #expect(store.hounds.map(\.isConnected) == [true, true, true, false])
    }

    @Test func aDropAfterResumingMarksEveryHoundOffline() async throws {
        try await connectAndWaitForAllHounds()
        store.suspend()
        try #require(try await eventually { store.connectionState == .disconnected })

        store.connect()
        try #require(try await eventually { store.connectionState == .connected })
        fake.dropConnection()
        #expect(try await eventually { store.hounds.allSatisfy { !$0.isConnected } })
    }

    @Test func suspendWhileDisconnectedDoesntSpareTheNextDrop() async throws {
        store.suspend()
        try await connectAndWaitForAllHounds()
        fake.dropConnection()
        #expect(try await eventually { store.hounds.allSatisfy { !$0.isConnected } })
    }
}
