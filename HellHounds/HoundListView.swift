//
//  HoundListView.swift
//  HellHounds
//
//  The hound list: a connection banner, a master card that drives every
//  hound, and one card per discovered hound with the name and look the
//  user gave it. Hounds the user named that haven't reported get a small
//  card saying so.
//

import SwiftData
import SwiftUI

struct HoundListView: View {
    let store: HoundStore
    let profileBroker: String

    @Query private var profiles: [HoundProfile]
    @Environment(\.modelContext) private var modelContext
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
                                edit: { editTarget = EditTarget(index: index, look: look) }
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
