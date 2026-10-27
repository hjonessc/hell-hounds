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
    ///   `-fakeHoundCount 6` sets how many (default 4).
    /// - `-mqttHost localhost` (optionally `-mqttPort 1884`): a local broker instead of the
    ///   one in Settings; see `BrokerAddress.fromLaunchArguments`.
    static var usesFakeTransport: Bool {
        let environment = ProcessInfo.processInfo.environment
        let isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestSessionIdentifier"] != nil
        return isUnitTestHost || UserDefaults.standard.bool(forKey: "useFakeTransport")
    }

    @MainActor
    static func makeTransport(broker: BrokerAddress) -> any MQTTTransport {
        if usesFakeTransport {
            let count = UserDefaults.standard.integer(forKey: "fakeHoundCount")
            return FakeMQTTTransport(hounds: FakeMQTTTransport.hounds(count: count == 0 ? 4 : count))
        }
        return MQTTNIOTransport(host: broker.host, port: broker.port)
    }
}
