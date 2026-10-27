//
//  HellHoundsApp.swift
//  HellHounds
//

import SwiftUI

@main
struct HellHoundsApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Hounds", systemImage: "pawprint.fill") {
                    HoundListView(store: model.store)
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView(model: model)
                }
            }
            .tint(.orange)
            .tabBarMinimizeBehavior(.onScrollDown)
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
