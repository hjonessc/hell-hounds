//
//  SettingsView.swift
//  HellHounds
//
//  Broker host and port, what the app is connected to, help, the event
//  log and debug mode.
//

import SwiftUI

/// Debug mode shows extra details on each hound's card.
enum DebugMode {
    static let key = "debugMode"
}

struct SettingsView: View {
    let model: AppModel

    @State private var host = ""
    @State private var port = ""
    @AppStorage(DebugMode.key) private var debugMode = false

    private var draft: BrokerAddress? { BrokerAddress(host: host, portText: port) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings-host")
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("settings-port")
                    Button("Connect to This Broker") {
                        if let draft { model.useBroker(draft) }
                    }
                    .disabled(draft == nil || draft == model.broker)
                    .accessibilityIdentifier("settings-connect")
                } header: {
                    Text("MQTT Broker")
                } footer: {
                    Text(brokerFooter)
                }
                .disabled(model.isBrokerLocked)

                if !model.isBrokerLocked && !model.broker.isPublicBroker {
                    Section {
                        Button("Use the Public Broker") { model.useBroker(.publicBroker) }
                    } footer: {
                        Text("\(BrokerAddress.publicBroker.host), the broker the hounds' firmware uses.")
                    }
                }

                Section("Connection") {
                    LabeledContent("Broker", value: "\(model.broker.host):\(model.broker.port)")
                    LabeledContent("Status", value: statusText)
                    if let connectedAt = model.store.connectedAt {
                        LabeledContent(model.store.connectionState == .connected ? "Connected Since" : "Last Connected") {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(connectedAt.timeAndAge(now: context.date))
                            }
                        }
                        .accessibilityIdentifier("settings-connected-at")
                    }
                    if model.store.connectionState != .connected, let disconnectedAt = model.store.disconnectedAt {
                        LabeledContent("Disconnected") {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(disconnectedAt.timeAndAge(now: context.date))
                            }
                        }
                    }
                    LabeledContent("Hounds Found", value: "\(model.store.hounds.count)")
                }

                Section {
                    NavigationLink("How It Works & Troubleshooting") { HelpView() }
                        .accessibilityIdentifier("settings-help")
                    NavigationLink("Event Log") { EventLogView(log: model.log, profileBroker: model.profileBrokerKey) }
                        .accessibilityIdentifier("settings-event-log")
                    Toggle("Debug Mode", isOn: $debugMode)
                        .accessibilityIdentifier("settings-debug-mode")
                } header: {
                    Text("Help")
                } footer: {
                    Text("Debug mode adds details to each hound's card: when it was last heard, battery voltage, message counts and its MQTT topic.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: model.broker, initial: true) { _, broker in
                host = broker.host
                port = String(broker.port)
            }
        }
    }

    private var brokerFooter: String {
        if model.usesFakeTransport {
            return "Running on in-process fake hounds (-useFakeTransport); no broker is used."
        }
        if model.isBrokerLocked {
            return "Set by the -mqttHost launch argument for this run."
        }
        if model.broker.isPublicBroker {
            return "The public broker is shared: anyone on it can see and switch these hounds."
        }
        return "Saved on this device. Hounds on another broker are listed afresh."
    }

    private var statusText: String {
        switch model.store.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Not connected"
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
