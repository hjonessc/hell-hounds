//
//  MQTTTransport.swift
//  HellHounds
//
//  The seam between the app and an MQTT client library (ADR 0002). The model
//  only sees this protocol; each library gets one adapter file.
//

import Foundation

struct MQTTMessage: Equatable, Sendable {
    let topic: String
    let payload: String
}

enum MQTTConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

enum MQTTTransportEvent: Equatable, Sendable {
    case stateChanged(MQTTConnectionState)
    case message(MQTTMessage)
}

@MainActor
protocol MQTTTransport: AnyObject {
    /// Every state change and incoming message, in order. Single consumer.
    var events: AsyncStream<MQTTTransportEvent> { get }

    func connect()
    func disconnect()
    /// Subscriptions don't survive a reconnect; resubscribe on `.connected`.
    func subscribe(to topicFilter: String)
    func publish(_ payload: String, to topic: String)
}
