//
//  HoundListView.swift
//  HellHounds
//
//  The hound list: a connection banner, a master card that drives every
//  hound, and one card per discovered hound.
//

import SwiftUI

struct HoundListView: View {
    let store: HoundStore

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
                        ForEach(store.hounds) { hound in
                            HoundCard(
                                title: "Hound \(hound.index + 1)",
                                systemImage: "pawprint.fill",
                                hound: hound,
                                accessibilityPrefix: "hound-\(hound.index)",
                                setOn: { store.setOn($0, houndIndex: hound.index) },
                                setBrightness: { store.setBrightness($0, houndIndex: hound.index) }
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
        }
    }
}

private struct HoundCard: View {
    static let background = Color(red: 75 / 255, green: 10 / 255, blue: 10 / 255)  // dark blood red, as in 2019

    let title: String
    let systemImage: String
    let hound: Hound
    let accessibilityPrefix: String
    let setOn: @MainActor (Bool) -> Void
    let setBrightness: @MainActor (Int) -> Void

    /// The slider's value while dragging and until the hound reports back.
    @State private var draftBrightness: Double?

    private var brightness: Double { draftBrightness ?? Double(hound.brightness) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(hound.isOn ? .orange : .secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.headline)
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
            .background(.thinMaterial, in: .rect(cornerRadius: 20))
            .accessibilityIdentifier("connection-banner")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Six hounds") {
    let fake = FakeMQTTTransport(hounds: FakeMQTTTransport.hounds(count: 6))
    let store = HoundStore(transport: fake)
    HoundListView(store: store)
        .task { store.connect() }
}

#Preview("Disconnected") {
    HoundListView(store: HoundStore(transport: FakeMQTTTransport()))
}
