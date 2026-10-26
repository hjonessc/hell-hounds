//
//  FakeMQTTTransportTests.swift
//  HellHoundsTests
//

import Testing
@testable import HellHounds

struct FakeMQTTTransportTests {
    @Test(arguments: [
        ("a/b/c", "a/b/c", true),
        ("a/b/c", "a/+/c", true),
        ("a/b/c", "a/#", true),
        ("a/b/c", "#", true),
        ("a/b/c", "a/b", false),
        ("a/b", "a/b/c", false),
        ("a/b/c", "a/+", false),
        ("a/b/c", "a/x/c", false),
        ("HellHounds-MQTT/3/status-json", "HellHounds-MQTT/+/status-json", true),
    ])
    func topicFilterMatching(topic: String, filter: String, matches: Bool) {
        #expect(FakeMQTTTransport.topic(topic, matches: filter) == matches)
    }

    @MainActor
    @Test func onlySubscribedTopicsAreDelivered() async {
        let fake = FakeMQTTTransport()
        var iterator = fake.events.makeAsyncIterator()
        fake.connect()
        #expect(await iterator.next() == .stateChanged(.connecting))
        #expect(await iterator.next() == .stateChanged(.connected))

        fake.subscribe(to: HoundProtocol.topic(.statusJSON, index: 1))
        fake.sendStatus(index: 0)  // not subscribed: dropped
        fake.sendStatus(index: 1)
        let event = await iterator.next()
        #expect(event == .message(MQTTMessage(
            topic: "HellHounds-MQTT/1/status-json",
            payload: #"{"ledState":false,"ledLvl":50,"battery":70}"#
        )))
    }

    @MainActor
    @Test func nothingIsSentOrRecordedWhileDisconnected() {
        let fake = FakeMQTTTransport()
        fake.subscribe(to: "#")
        fake.publish("1", to: HoundProtocol.topic(.setState, index: 0))
        #expect(fake.published.isEmpty)
        #expect(fake.subscriptions.isEmpty)
        #expect(fake.hounds[0]?.isOn == false)
    }
}
