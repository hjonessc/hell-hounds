//
//  HoundStoreTests.swift
//  HellHoundsTests
//
//  Discovery and the status / set-state / set-level round trip through
//  HoundStore and the in-app fake transport; also refresh, identify and
//  what debug mode and the event log show.
//

import Foundation
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

    /// Just what the card shows, without the debug details.
    private func shown(_ hound: Hound?) -> Hound? {
        hound.map { Hound(index: $0.index, isConnected: $0.isConnected, isOn: $0.isOn, brightness: $0.brightness, battery: $0.battery) }
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
        #expect(fake.subscriptions == ["HellHounds-MQTT/+/status-json", "HellHounds-MQTT/+/BatStats"])
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
        #expect(shown(store.hounds.last) == Hound(index: 12, isConnected: true, isOn: true, brightness: 5, battery: 60))

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
        #expect(shown(store.hounds[0]) == Hound(index: 0, isConnected: true, isOn: false, brightness: 50, battery: 100))
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
        #expect(fake.subscriptions.count == 2)
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

    // MARK: - Debug details

    @Test func eachHoundRecordsWhenItWasHeardAndItsMessages() async throws {
        let clock = Clock()
        let fake = FakeMQTTTransport()
        let store = HoundStore(transport: fake, statusPollDelay: .zero, now: { clock.now })
        store.connect()
        #expect(try await eventually { store.hounds.count == 4 && store.hounds.allSatisfy { $0.batteryStats != nil } })
        #expect(store.connectedAt == clock.now)
        #expect(store.hounds[1].lastHeard == clock.now)
        #expect(store.hounds[1].lastStatusPayload == #"{"ledState":false,"ledLvl":50,"battery":70}"#)
        #expect(store.hounds[1].messagesReceived == 2)  // status-json and BatStats
        #expect(store.hounds[1].batteryStats == BatteryStats(charge: 70, voltage: 3.93, milliamps: -79))

        clock.now += 60
        store.setOn(true, houndIndex: 1)
        #expect(try await eventually { store.hounds[1].isOn })
        #expect(store.hounds[1].lastHeard == clock.now)
        #expect(store.hounds[1].messagesSent == 2, "the poll and the command")

        fake.dropConnection()
        #expect(try await eventually { store.disconnectedAt == clock.now })
    }

    @Test func batteryStatsFromAnUnknownHoundAreIgnored() async throws {
        fake.hounds = [:]
        store.connect()
        try #require(try await eventually { store.connectionState == .connected })
        fake.deliver(MQTTMessage(topic: HoundProtocol.topic(.batStats, index: 7), payload: " SOC: 90 %\n4.00 V | -79 mA"))
        fake.deliver(status(index: 2, #"{"ledState":true}"#))
        #expect(try await eventually { store.hounds.count == 1 })
        #expect(store.hounds.map(\.index) == [2])
    }

    // MARK: - Refresh

    @Test func refreshAsksEveryHoundAgain() async throws {
        try await connectAndWaitForAllHounds()
        let before = fake.published.count
        fake.hounds[1]?.battery = 12
        await store.refresh()
        #expect(fake.published.dropFirst(before).map(\.topic) == probeTopics)
        #expect(store.hounds[1].battery == 12)
    }

    @Test func refreshConnectsWhenDisconnected() async throws {
        await store.refresh()
        #expect(store.connectionState == .connected)
        #expect(store.hounds.count == 4)
    }

    @Test func refreshMarksHoundsThatDontAnswerOffline() async throws {
        let fake = FakeMQTTTransport()
        let store = HoundStore(transport: fake, statusPollDelay: .zero, answerTimeout: .milliseconds(100))
        store.connect()
        try #require(try await eventually { store.hounds.count == 4 && !store.isDiscovering })
        fake.hounds[2] = nil
        await store.refresh()
        #expect(store.hounds.map(\.isConnected) == [true, true, false, true])
    }

    // MARK: - Identify

    /// Its own fake: two stores on one transport would split its events.
    private func identifyStore(_ fake: FakeMQTTTransport) -> HoundStore {
        HoundStore(transport: fake, statusPollDelay: .zero, identifyDuration: .milliseconds(200), identifyBlink: .milliseconds(20))
    }

    private func sent(_ fake: FakeMQTTTransport, to index: Int, after count: Int) -> [String] {
        fake.published.dropFirst(count)
            .filter { HoundProtocol.index(fromTopic: $0.topic, leaf: .setState) == index || HoundProtocol.index(fromTopic: $0.topic, leaf: .setLevel) == index }
            .map { "\($0.topic.split(separator: "/").last!) \($0.payload)" }
    }

    @Test func identifyBlinksThenGoesBackToHowItWas() async throws {
        let fake = FakeMQTTTransport(hounds: [0: .init(isOn: true, level: 80)])
        let store = identifyStore(fake)
        store.connect()
        try #require(try await eventually { store.hounds.first?.isConnected == true })
        let before = fake.published.count

        store.toggleIdentify(houndIndex: 0)
        #expect(store.identifying == [0])
        #expect(try await eventually { store.identifying.isEmpty })
        try await Task.sleep(for: .milliseconds(60))  // the second restore

        let commands = sent(fake, to: 0, after: before)
        #expect(commands.prefix(4) == ["set-state 0", "set-state 1", "set-state 0", "set-state 1"])
        #expect(commands.suffix(3) == ["set-level 80", "set-state 1", "set-state 1"])
        #expect(fake.hounds[0] == .init(isOn: true, level: 80))
    }

    @Test func identifyingADimHoundTurnsItUpAndBack() async throws {
        let fake = FakeMQTTTransport(hounds: [0: .init(isOn: false, level: 10)])
        let store = identifyStore(fake)
        store.connect()
        try #require(try await eventually { store.hounds.first?.isConnected == true })
        let before = fake.published.count

        store.toggleIdentify(houndIndex: 0)
        #expect(try await eventually { sent(fake, to: 0, after: before).count >= 2 })
        #expect(sent(fake, to: 0, after: before).prefix(2) == ["set-level 100", "set-state 1"])
        store.toggleIdentify(houndIndex: 0)  // stopped early
        #expect(store.identifying.isEmpty)
        #expect(sent(fake, to: 0, after: before).suffix(2) == ["set-level 10", "set-state 0"])
        #expect(try await eventually { fake.hounds[0] == .init(isOn: false, level: 10) })
    }

    @Test func aCommandStopsIdentifyingAndWins() async throws {
        let fake = FakeMQTTTransport(hounds: [0: .init(isOn: false, level: 80)])
        let store = identifyStore(fake)
        store.connect()
        try #require(try await eventually { store.hounds.first?.isConnected == true })

        store.toggleIdentify(houndIndex: 0)
        store.setOn(true, houndIndex: 0)
        #expect(store.identifying.isEmpty)
        let before = fake.published.count
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.published.count == before, "no more blinking and no restore")
        #expect(fake.hounds[0]?.isOn == true)
    }

    @Test func offlineHoundsDontIdentify() async throws {
        store.toggleIdentify(houndIndex: 0)
        #expect(store.identifying.isEmpty)
    }

    // MARK: - Event log

    @Test func theLogTellsTheStory() async throws {
        let log = EventLog()
        let fake = FakeMQTTTransport(hounds: [0: .init(), 1: .init()])
        let store = HoundStore(transport: fake, log: log, statusPollDelay: .zero, answerTimeout: .milliseconds(100))
        store.connect()
        try #require(try await eventually { store.hounds.count == 2 && !store.isDiscovering })
        store.setOn(true, houndIndex: 1)
        try #require(try await eventually { store.hounds[1].isOn })
        fake.hounds[0] = nil
        await store.refresh()
        fake.deliver(status(index: 1, "garbage"))
        try #require(try await eventually { log.entries.last?.text.hasPrefix("Ignored") == true })

        #expect(log.entries.map(\.text) == [
            "Connected to the broker",
            "Asked hounds 1, 2, 3, 4, 5, 6, 7, 8 for their status",
            "Found: off, 50 %, battery 100 %",
            "Found: off, 50 %, battery 100 %",
            "Switch on (set-state 1)",
            "Status: on, 50 %, battery 100 %",
            "Refresh: asking every hound for its status",
            "Asked hounds 1, 2, 3, 4, 5, 6, 7, 8 for their status",
            "Status: on, 50 %, battery 100 %",
            "Didn't answer; now offline",
            "Ignored a status it couldn't read: garbage",
        ])
        #expect(log.entries.map(\.houndIndex) == [nil, nil, 0, 1, 1, 1, nil, nil, 1, 0, 1])
    }
}

/// A clock the test moves by hand.
@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}
