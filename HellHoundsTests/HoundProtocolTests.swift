//
//  HoundProtocolTests.swift
//  HellHoundsTests
//
//  Topics, payloads and status parsing from docs/PROTOCOL.md.
//

import Testing
@testable import HellHounds

struct HoundProtocolTests {
    @Test func topicsFollowPrefixIndexLeaf() {
        #expect(HoundProtocol.topic(.setState, index: 2) == "HellHounds-MQTT/2/set-state")
        #expect(HoundProtocol.topic(.setLevel, index: 0) == "HellHounds-MQTT/0/set-level")
        #expect(HoundProtocol.topic(.getStatus, index: 3) == "HellHounds-MQTT/3/msg")
        #expect(HoundProtocol.topic(.statusJSON, index: 1) == "HellHounds-MQTT/1/status-json")
    }

    @Test func setStateSendsOneForOn() {
        #expect(HoundProtocol.setStatePayload(isOn: true) == "1")
        #expect(HoundProtocol.setStatePayload(isOn: false) == "0")
    }

    @Test(arguments: [(42, "42"), (0, "0"), (100, "100"), (-5, "0"), (150, "100")])
    func setLevelIsClampedTo0Through100(brightness: Int, payload: String) {
        #expect(HoundProtocol.setLevelPayload(brightness: brightness) == payload)
    }

    @Test(arguments: [
        ("HellHounds-MQTT/0/status-json", 0),
        ("HellHounds-MQTT/12/status-json", 12),
    ])
    func statusIndexReadsTheIndex(topic: String, index: Int) {
        #expect(HoundProtocol.statusIndex(fromTopic: topic) == index)
    }

    @Test(arguments: [
        "HellHounds-MQTT/x/status-json",
        "HellHounds-MQTT/1/status",
        "HellHounds-MQTT/1/BatStats",
        "Other/1/status-json",
        "HellHounds-MQTT/1/status-json/extra",
        "HellHounds-MQTT/status-json",
    ])
    func statusIndexRejectsOtherTopics(topic: String) {
        #expect(HoundProtocol.statusIndex(fromTopic: topic) == nil)
    }
}

struct HoundStatusTests {
    @Test func realFirmwareSendsBooleanLedState() {
        let status = HoundStatus(payload: #"{"ledState":true,"ledLvl":81,"battery":90}"#)
        #expect(status == HoundStatus(isOn: true, brightness: 81, battery: 90))
        #expect(HoundStatus(payload: #"{"ledState":false,"ledLvl":81,"battery":90}"#)?.isOn == false)
    }

    @Test func integerLedStateWithOneMeaningOn() {
        #expect(HoundStatus(payload: #"{"ledState":1,"ledLvl":42,"battery":87}"#) == HoundStatus(isOn: true, brightness: 42, battery: 87))
        #expect(HoundStatus(payload: #"{"ledState":0,"ledLvl":42,"battery":87}"#)?.isOn == false)
        #expect(HoundStatus(payload: #"{"ledState":2,"ledLvl":42,"battery":87}"#)?.isOn == false)
    }

    @Test func backslashEscapedJSONIsAccepted() {
        let status = HoundStatus(payload: #"{\"ledState\":1,\"ledLvl\":50,\"battery\":70}"#)
        #expect(status == HoundStatus(isOn: true, brightness: 50, battery: 70))
    }

    @Test func missingFieldsAreNilAndMissingLedStateIsOff() {
        #expect(HoundStatus(payload: #"{"ledLvl":5}"#) == HoundStatus(isOn: false, brightness: 5, battery: nil))
        #expect(HoundStatus(payload: "{}") == HoundStatus(isOn: false, brightness: nil, battery: nil))
    }

    @Test(arguments: [
        "nope",
        "",
        #"{"ledState":"on"}"#,
        #"{"ledLvl":"42"}"#,
        #"{"battery":87.5}"#,
        "[1,2,3]",
    ])
    func malformedPayloadsAreRejected(payload: String) {
        #expect(HoundStatus(payload: payload) == nil)
    }
}
