//
//  MQTTNIOTransport.swift
//  HellHounds
//
//  MQTTTransport on MQTTNIO 3 (ADR 0002). MQTTNIO has no auto-reconnect, so
//  this adapter runs its own loop: connect, serve until the connection
//  closes, wait with backoff, repeat until `disconnect()`.
//

import Foundation
import MQTTNIO
import NIOCore
import NIOTransportServices

@MainActor
final class MQTTNIOTransport: MQTTTransport {
    let events: AsyncStream<MQTTTransportEvent>
    private let continuation: AsyncStream<MQTTTransportEvent>.Continuation

    private let address: MQTTServerAddress
    private let configuration: MQTTConnectionConfiguration
    private let clientID = "HellHounds-Test-" + String(ProcessInfo().processIdentifier)

    private enum Command {
        case subscribe(String)
        case publish(String, to: String)
    }

    private var runTask: Task<Void, Never>?
    /// True while `run()` sleeps between attempts.
    private var isWaitingToRetry = false
    private var connection: MQTTConnection?
    /// Commands for the current connection; nil while disconnected, when
    /// commands are dropped (the store resubscribes on every `.connected`).
    private var commands: AsyncStream<Command>.Continuation?

    init(host: String = "broker.hivemq.com", port: Int = 1883) {
        (events, continuation) = AsyncStream.makeStream()
        address = .hostname(host, port: port)
        configuration = MQTTConnectionConfiguration(
            versionConfiguration: .v3_1_1(
                will: .init(topicName: "/will", payload: ByteBuffer(string: "dieout"), qos: .atMostOnce)
            ),
            keepAliveInterval: .seconds(60),
            // Over NIOTransportServices a refused connection only fails at this
            // timeout (default 10 s), and the banner shows "Connecting…" until then.
            connectTimeout: .seconds(5)
        )
    }

    deinit {
        continuation.finish()
    }

    /// Starts the connection loop; while the loop waits to retry, retries now.
    func connect() {
        if runTask != nil {
            guard isWaitingToRetry else { return }
            // Cancelling ends only the backoff sleep; there's no connection to close.
            runTask?.cancel()
        }
        isWaitingToRetry = false
        runTask = Task { await run() }
    }

    func disconnect() {
        runTask?.cancel()
        runTask = nil
        isWaitingToRetry = false
        // Ends the current connection's waitOnClose, so run() unwinds.
        connection?.close()
    }

    func subscribe(to topicFilter: String) {
        commands?.yield(.subscribe(topicFilter))
    }

    func publish(_ payload: String, to topic: String) {
        commands?.yield(.publish(payload, to: topic))
    }

    // MARK: - Connection loop

    private static let initialBackoff: Duration = .seconds(1)
    private static let maxBackoff: Duration = .seconds(30)

    private func run() async {
        var backoff = Self.initialBackoff
        while !Task.isCancelled {
            continuation.yield(.stateChanged(.connecting))
            do {
                try await MQTTConnection.withConnection(
                    address: address,
                    configuration: configuration,
                    identifier: clientID,
                    eventLoop: NIOTSEventLoopGroup.singleton.any()
                ) { connection in
                    backoff = Self.initialBackoff
                    await serve(connection)
                }
            } catch {
                print("MQTT connection failed: \(error)")
                continuation.yield(.failed("Connection failed: \(error)"))
            }
            continuation.yield(.stateChanged(.disconnected))
            guard !Task.isCancelled else { return }
            isWaitingToRetry = true
            do {
                try await Task.sleep(for: backoff)
            } catch {
                return  // connect() replaced this loop or disconnect() stopped it
            }
            isWaitingToRetry = false
            backoff = min(backoff * 2, Self.maxBackoff)
        }
    }

    /// Runs commands on `connection` in order until it closes.
    private func serve(_ connection: MQTTConnection) async {
        let (commandStream, commands) = AsyncStream<Command>.makeStream()
        self.connection = connection
        self.commands = commands
        defer {
            // A reconnect after disconnect() may already have replaced these.
            if self.connection === connection {
                self.connection = nil
                self.commands = nil
            }
        }
        // disconnect() may have run while CONNECT was in flight.
        guard !Task.isCancelled else { return }
        continuation.yield(.stateChanged(.connected))

        let events = continuation
        await withDiscardingTaskGroup { group in
            group.addTask {
                await connection.waitOnClose()
                commands.finish()
            }
            for await command in commandStream {
                switch command {
                case .publish(let payload, let topic):
                    do {
                        try await connection.publish(to: topic, payload: ByteBuffer(string: payload), qos: .atMostOnce)
                    } catch {
                        print("MQTT publish to \(topic) failed: \(error)")
                        events.yield(.failed("Sending to \(topic) failed: \(error)"))
                    }
                case .subscribe(let topicFilter):
                    group.addTask {
                        do {
                            try await connection.subscribe(to: [.init(topicFilter: topicFilter, qos: .atLeastOnce)]) { subscription in
                                for try await message in subscription {
                                    events.yield(.message(MQTTMessage(topic: message.topicName, payload: String(buffer: message.payload))))
                                }
                            }
                        } catch {
                            print("MQTT subscription to \(topicFilter) ended: \(error)")
                            events.yield(.failed("Listening on \(topicFilter) stopped: \(error)"))
                        }
                    }
                }
            }
            group.cancelAll()
        }
    }
}
