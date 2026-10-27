//
//  BrokerAddress.swift
//  HellHounds
//
//  Where the app connects: the stored setting, unless a launch argument says
//  otherwise.
//

import Foundation

struct BrokerAddress: Equatable, Sendable {
    let host: String
    let port: Int

    static let publicBroker = BrokerAddress(validHost: "broker.hivemq.com", port: 1883)

    private init(validHost: String, port: Int) {
        host = validHost
        self.port = port
    }

    /// Nil unless `host` is a bare host name or address (no scheme, path or
    /// spaces) and `port` is 1...65535.
    init?(host: String, port: Int) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" }),
              (1...65535).contains(port)
        else { return nil }
        self.init(validHost: host, port: port)
    }

    init?(host: String, portText: String) {
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(host: host, port: port)
    }

    var isPublicBroker: Bool { self == .publicBroker }

    // MARK: - Sources

    private static let hostKey = "brokerHost"
    private static let portKey = "brokerPort"

    /// `-mqttHost` (and optionally `-mqttPort`) from the launch arguments,
    /// i.e. UserDefaults' argument domain.
    static func fromLaunchArguments(_ arguments: [String: Any]) -> BrokerAddress? {
        guard let host = arguments["mqttHost"] as? String else { return nil }
        let port = (arguments["mqttPort"] as? String).flatMap(Int.init) ?? (arguments["mqttPort"] as? Int) ?? 1883
        return BrokerAddress(host: host, port: port)
    }

    /// The broker saved in Settings, if any.
    static func stored(in defaults: UserDefaults) -> BrokerAddress? {
        guard let host = defaults.string(forKey: hostKey) else { return nil }
        return BrokerAddress(host: host, port: defaults.integer(forKey: portKey))
    }

    func store(in defaults: UserDefaults) {
        defaults.set(host, forKey: Self.hostKey)
        defaults.set(port, forKey: Self.portKey)
    }
}
