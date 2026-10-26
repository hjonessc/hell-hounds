//
//  HoundListView.swift
//  HellHounds
//
//  Interim plain list (Phase 3 step 1); the styled cards come in step 3.
//

import SwiftUI

struct HoundListView: View {
    let store: HoundStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HoundRow(
                        title: "All hounds",
                        hound: store.master,
                        setOn: { store.setAllOn($0) },
                        setBrightness: { store.setAllBrightness($0) }
                    )
                    .accessibilityIdentifier("hound-master")
                }
                Section("Hounds") {
                    ForEach(store.hounds) { hound in
                        HoundRow(
                            title: "Hound \(hound.index + 1)",
                            hound: hound,
                            setOn: { store.setOn($0, houndIndex: hound.index) },
                            setBrightness: { store.setBrightness($0, houndIndex: hound.index) }
                        )
                        .accessibilityIdentifier("hound-\(hound.index)")
                    }
                }
            }
            .navigationTitle("Hellhounds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionLabel(state: store.connectionState)
                }
            }
        }
    }
}

private struct HoundRow: View {
    let title: String
    let hound: Hound
    let setOn: @MainActor (Bool) -> Void
    let setBrightness: @MainActor (Int) -> Void

    /// The slider's value while dragging and until the hound reports back.
    @State private var draftBrightness: Double?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: Binding(get: { hound.isOn }, set: setOn)) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(hound.isConnected ? "\(hound.battery)%" : "offline")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("toggle")
            Slider(
                value: Binding(
                    get: { draftBrightness ?? Double(hound.brightness) },
                    set: { draftBrightness = $0 }
                ),
                in: 0...100
            ) { isEditing in
                // Send on release, like the old UISlider with isContinuous = false.
                if !isEditing, let draftBrightness {
                    setBrightness(Int(draftBrightness.rounded()))
                }
            }
            .accessibilityIdentifier("slider")
        }
        .opacity(hound.isConnected ? 1 : 0.4)
        .onChange(of: hound.brightness) { draftBrightness = nil }
    }
}

private struct ConnectionLabel: View {
    let state: MQTTConnectionState

    var body: some View {
        switch state {
        case .connected: Label("Connected", systemImage: "antenna.radiowaves.left.and.right")
        case .connecting: ProgressView()
        case .disconnected: Label("Disconnected", systemImage: "antenna.radiowaves.left.and.right.slash")
        }
    }
}
