//
//  HoundListView.swift
//  HellHounds
//
//  The hound list: a connection banner, a master card that drives every
//  hound, and one card per discovered hound with the name and look the
//  user gave it.
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
                    if store.hounds.isEmpty {
                        if store.connectionState == .connected {
                            ContentUnavailableView(
                                "No Hounds Yet",
                                systemImage: "pawprint",
                                description: Text("Hounds appear here as soon as they report.")
                            )
                        }
                    } else {
                        HoundCard(
                            title: "All Hounds",
                            systemImage: "flame.fill",
                            hound: store.master,
                            accessibilityPrefix: "hound-master",
                            setOn: { store.setAllOn($0) },
                            setBrightness: { store.setAllBrightness($0) }
                        )
                        let looks = HoundProfile.newestByIndex(profiles)
                        ForEach(store.hounds) { hound in
                            let look = HoundLook(looks[hound.index])
                            HoundCard(
                                title: look.title(houndIndex: hound.index),
                                systemImage: look.symbol,
                                photoData: look.photoData,
                                hound: hound,
                                accessibilityPrefix: "hound-\(hound.index)",
                                setOn: { store.setOn($0, houndIndex: hound.index) },
                                setBrightness: { store.setBrightness($0, houndIndex: hound.index) },
                                edit: { editTarget = EditTarget(index: hound.index, look: look) }
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .animation(.default, value: store.hounds.map(\.index))
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
            Text(title)
                .font(.headline)
                .lineLimit(1)
        }
        .contentShape(.rect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let edit {
                    Button(action: edit) { label }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(title)")
                        .accessibilityIdentifier("\(accessibilityPrefix)-edit")
                } else {
                    label
                }
                Spacer()
                if hound.isConnected {
                    BatteryIndicator(level: hound.battery)
                } else {
                    Text("Offline")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Toggle(title, isOn: Binding(get: { hound.isOn }, set: setOn))
                    .labelsHidden()
                    .accessibilityIdentifier("\(accessibilityPrefix)-toggle")
            }
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
        }
        .tint(.orange)
        .padding()
        .background(Self.background, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .environment(\.colorScheme, .dark)
        .opacity(hound.isConnected ? 1 : 0.45)
        .disabled(!hound.isConnected)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityPrefix)
        .onChange(of: hound.brightness) { draftBrightness = nil }
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
