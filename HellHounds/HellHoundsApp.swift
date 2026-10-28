//
//  HellHoundsApp.swift
//  HellHounds
//

import SwiftData
import SwiftUI

@main
struct HellHoundsApp: App {
    @State private var model = AppModel()
    @State private var profiles = ProfileStore.makeContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Hounds", systemImage: "pawprint.fill") {
                    HoundListView(store: model.store, profileBroker: model.profileBrokerKey)
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView(model: model)
                }
            }
            .tint(.orange)
            .tabBarMinimizeBehavior(.onScrollDown)
            .modelContainer(profiles)
        }
        // Stay connected only while in the foreground; the transport reconnects on its own in between.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.store.connect()
            case .background: model.store.disconnect()
            default: break
            }
        }
    }
}
