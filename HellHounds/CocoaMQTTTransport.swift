//
//  CocoaMQTTTransport.swift
//  HellHounds
//
//  MQTTTransport on CocoaMQTT 2.x. Interim adapter until MQTTNIO lands, and
//  the fallback named in ADR 0002.
//

import Foundation
import CocoaMQTT

@MainActor
final class CocoaMQTTTransport: MQTTTransport {
    let events: AsyncStream<MQTTTransportEvent>
    private let continuation: AsyncStream<MQTTTransportEvent>.Continuation
    private let mqtt: CocoaMQTT

    init(host: String = "broker.hivemq.com", port: UInt16 = 1883) {
        (events, continuation) = AsyncStream.makeStream()
        let clientID = "HellHounds-Test-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
        mqtt.username = ""
        mqtt.password = ""
        mqtt.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
        mqtt.keepAlive = 60

        // AsyncStream.Continuation is thread-safe, so the callbacks just yield.
        let continuation = continuation
        mqtt.didConnectAck = { _, ack in
            print("MQTT connect ack: \(ack)")
            continuation.yield(.stateChanged(ack == .accept ? .connected : .disconnected))
        }
        mqtt.didDisconnect = { _, error in
            print("MQTT disconnected: \(error.map { "\($0)" } ?? "no error")")
            continuation.yield(.stateChanged(.disconnected))
        }
        mqtt.didReceiveMessage = { _, message, _ in
            guard let payload = message.string else { return }
            continuation.yield(.message(MQTTMessage(topic: message.topic, payload: payload)))
        }
    }

    deinit {
        continuation.finish()
    }

    func connect() {
        continuation.yield(.stateChanged(.connecting))
        if !mqtt.connect() {
            continuation.yield(.stateChanged(.disconnected))
        }
    }

    func disconnect() {
        mqtt.disconnect()
    }

    func subscribe(to topicFilter: String) {
        mqtt.subscribe(topicFilter, qos: .qos1)
    }

    func publish(_ payload: String, to topic: String) {
        mqtt.publish(topic, withString: payload, qos: .qos0)
    }
}
