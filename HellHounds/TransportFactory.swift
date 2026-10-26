//
//  TransportFactory.swift
//  HellHounds
//
//  Picks the MQTTTransport the app runs on.
//

import Foundation

enum TransportFactory {
    /// Launch arguments, read through UserDefaults:
    /// - `-useFakeTransport YES`: in-process fake hounds, no network (also used under unit tests).
    /// - `-mqttHost localhost` (optionally `-mqttPort 1884`): a local broker instead of the public one.
    @MainActor
    static func makeTransport() -> any MQTTTransport {
        let defaults = UserDefaults.standard
        let environment = ProcessInfo.processInfo.environment
        let isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestSessionIdentifier"] != nil
        if isUnitTestHost || defaults.bool(forKey: "useFakeTransport") {
            return FakeMQTTTransport()
        }
        return MQTTNIOTransport(
            host: defaults.string(forKey: "mqttHost") ?? "broker.hivemq.com",
            port: defaults.integer(forKey: "mqttPort").nonZero ?? 1883
        )
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
