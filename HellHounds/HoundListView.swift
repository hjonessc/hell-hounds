//
//  HoundListView.swift
//  HellHounds
//
//  The hound list: a connection banner, a master card that drives every
//  hound, and one card per discovered hound with the name and look the
//  user gave it. Hounds the user named that haven't reported get a small
//  card saying so. Pull down to ask every hound again; long-press a card to
//  make its hound blink. Debug mode (Settings) adds details to each card.
//

import SwiftData
import SwiftUI

struct HoundListView: View {
    let store: HoundStore
    let profileBroker: String

    @Query private var profiles: [HoundProfile]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DebugMode.key) private var debugMode = false
    @State private var editTarget: EditTarget?

    init(store: HoundStore, profileBroker: String) {
        self.store = store
        self.profileBroker = profileBroker
        _profiles = Query(filter: HoundProfile.predicate(broker: profileBroker))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ConnectionBanner(state: store.connectionState, connect: { store.connect() })
                    let looks = HoundProfile.newestByIndex(profiles)
                    let found = Dictionary(uniqueKeysWithValues: store.hounds.map { ($0.index, $0) })
                    let saved = looks.filter { $0.value.isCustomised }.keys
                    let indices = Set(found.keys).union(saved).sorted()
                    if indices.isEmpty {
                        if store.connectionState == .connected {
                            ContentUnavailableView(
                                "No Hounds Yet",
                                systemImage: "pawprint",
                                description: Text("Hounds appear here as soon as they report.")
                            )
                        }
                    } else {
                        if !found.isEmpty {
                            HoundCard(
                                title: "All Hounds",
                                systemImage: "flame.fill",
                                hound: store.master,
                                accessibilityPrefix: "hound-master",
                                setOn: { store.setAllOn($0) },
                                setBrightness: { store.setAllBrightness($0) }
                            )
                        }
                        ForEach(indices, id: \.self) { index in
                            let look = HoundLook(looks[index])
                            HoundCard(
                                title: look.title(houndIndex: index),
                                systemImage: look.symbol,
                                photoData: look.photoData,
                                hound: found[index] ?? Hound(index: index),
                                notFound: found[index] != nil ? nil
                                    : store.isDiscovering || store.connectionState == .connecting ? "Looking…" : "Not found",
                                accessibilityPrefix: "hound-\(index)",
                                setOn: { store.setOn($0, houndIndex: index) },
                                setBrightness: { store.setBrightness($0, houndIndex: index) },
                                edit: { editTarget = EditTarget(index: index, look: look) },
                                isIdentifying: store.identifying.contains(index),
                                identify: { store.toggleIdentify(houndIndex: index) },
                                showsDebugDetails: debugMode
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .animation(.default, value: store.hounds.map(\.index))
                .animation(.default, value: profiles.count)
                .animation(.default, value: store.connectionState)
            }
            .refreshable { await store.refresh() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hellhounds")
            .sheet(item: $editTarget) { target in
                HoundEditSheet(houndIndex: target.index, look: target.look) { look in
                    try? modelContext.saveLook(look, broker: profileBroker, houndIndex: target.index)
                }
            }
        }
    }
}

private struct EditTarget: Identifiable {
    let index: Int
    let look: HoundLook
    var id: Int { index }
}

private struct HoundCard: View {
    static let background = Color(red: 75 / 255, green: 10 / 255, blue: 10 / 255)  // dark blood red, as in 2019

    let title: String
    let systemImage: String
    var photoData: Data?
    let hound: Hound
    /// Set for a hound the user named that hasn't reported: says so in place
    /// of the battery, and the card has no controls.
    var notFound: String?
    let accessibilityPrefix: String
    let setOn: @MainActor (Bool) -> Void
    let setBrightness: @MainActor (Int) -> Void
    /// Opens the edit sheet; nil for the master card.
    var edit: (@MainActor () -> Void)?
    var isIdentifying = false
    /// Starts or stops blinking; nil for the master card.
    var identify: (@MainActor () -> Void)?
    var showsDebugDetails = false

    private var canIdentify: Bool { identify != nil && hound.isConnected && notFound == nil }

    /// The slider's value while dragging and until the hound reports back.
    @State private var draftBrightness: Double?

    private var brightness: Double { draftBrightness ?? Double(hound.brightness) }

    private var label: some View {
        HStack(spacing: 10) {
            HoundAvatar(systemImage: systemImage, photoData: photoData, isOn: hound.isOn)
            // Long names shrink a little, then wrap to a second line.
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Group {
                    if let edit {
                        Button(action: edit) { label }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(title)")
                            .accessibilityIdentifier("\(accessibilityPrefix)-edit")
                    } else {
                        label
                    }
                }
                .layoutPriority(1)  // the name gets the room before the spacer
                Spacer(minLength: 0)
                // The name wraps first; what's on its right keeps its size.
                if let notFound {
                    Label(notFound, systemImage: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(notFound)
                        .accessibilityIdentifier("\(accessibilityPrefix)-status")
                } else {
                    if hound.isConnected {
                        BatteryIndicator(level: hound.battery)
                            .fixedSize()
                    } else {
                        Text("Offline")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Toggle(title, isOn: Binding(get: { hound.isOn }, set: setOn))
                        .labelsHidden()
                        .disabled(!hound.isConnected)
                        .accessibilityIdentifier("\(accessibilityPrefix)-toggle")
                }
            }
            if notFound == nil {
                brightnessRow
            }
            if isIdentifying {
                identifyingRow
            }
            if showsDebugDetails && identify != nil {
                DebugDetails(hound: hound)
                if canIdentify && !isIdentifying, let identify {
                    Button("Identify", systemImage: "light.beacon.max", action: identify)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("\(accessibilityPrefix)-identify")
                }
            }
        }
        .tint(.orange)
        .padding()
        .background(Self.background, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .environment(\.colorScheme, .dark)
        .opacity(hound.isConnected ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityPrefix)
        .onChange(of: hound.brightness) { draftBrightness = nil }
        .contextMenu {
            if canIdentify, let identify {
                Button(isIdentifying ? "Stop Blinking" : "Identify (Blink 30 s)",
                       systemImage: isIdentifying ? "stop.fill" : "light.beacon.max",
                       action: identify)
            }
            if let edit {
                Button("Edit", systemImage: "pencil", action: edit)
            }
        }
    }

    private var identifyingRow: some View {
        HStack {
            Label("Blinking so you can find it…", systemImage: "light.beacon.max")
                .symbolEffect(.pulse)
                .font(.subheadline)
            Spacer(minLength: 0)
            if let identify {
                Button("Stop", action: identify)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("\(accessibilityPrefix)-stop-identify")
            }
        }
    }

    private var brightnessRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Slider(
                value: Binding(get: { brightness }, set: { draftBrightness = $0 }),
                in: 0...100
            ) { isEditing in
                // Send on release, like the old UISlider with isContinuous = false.
                if !isEditing, let draftBrightness {
                    setBrightness(Int(draftBrightness.rounded()))
                }
            }
            .accessibilityLabel("\(title) brightness")
            .accessibilityIdentifier("\(accessibilityPrefix)-slider")
            Text("\(Int(brightness.rounded()))%")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .disabled(!hound.isConnected)
    }
}

/// The extra rows debug mode shows on each hound's card.
private struct DebugDetails: View {
    let hound: Hound

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Last heard") {
                if let lastHeard = hound.lastHeard {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(lastHeard.timeAndAge(now: context.date))
                    }
                } else {
                    Text("Not since launch")
                }
            }
            if let stats = hound.batteryStats {
                row("Battery") {
                    Text([
                        stats.voltage.map { "\($0.formatted(.number.precision(.fractionLength(2)))) V" },
                        stats.milliamps.map { "\($0) mA" },
                    ].compactMap(\.self).joined(separator: ", "))
                }
            }
            row("Messages") { Text("\(hound.messagesSent) sent, \(hound.messagesReceived) received") }
            row("Topic") { Text(verbatim: "\(HoundProtocol.topicPrefix)/\(hound.index)/").textSelection(.enabled) }
            if let payload = hound.lastStatusPayload {
                // Spaces after commas let the JSON wrap between fields.
                row("Status") { Text(verbatim: payload.replacingOccurrences(of: ",", with: ", ")).textSelection(.enabled) }
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hound-\(hound.index)-debug")
    }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label).gridColumnAlignment(.trailing)
            value()
        }
    }
}

private struct ConnectionBanner: View {
    let state: MQTTConnectionState
    let connect: @MainActor () -> Void

    var body: some View {
        if state != .connected {
            HStack(spacing: 12) {
                if state == .connecting {
                    ProgressView()
                    Text("Connecting…")
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    Text("Not connected")
                }
                Spacer(minLength: 0)
                if state == .disconnected {
                    // While the transport waits to retry, this retries now.
                    Button("Retry", action: connect)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .accessibilityIdentifier("connection-banner")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Six hounds") {
    let fake = FakeMQTTTransport(hounds: FakeMQTTTransport.hounds(count: 6))
    let store = HoundStore(transport: fake)
    HoundListView(store: store, profileBroker: HoundProfile.fakeBrokerKey)
        .task { store.connect() }
        .modelContainer(for: HoundProfile.self, inMemory: true)
}

#Preview("Disconnected") {
    HoundListView(store: HoundStore(transport: FakeMQTTTransport()), profileBroker: HoundProfile.fakeBrokerKey)
        .modelContainer(for: HoundProfile.self, inMemory: true)
}
