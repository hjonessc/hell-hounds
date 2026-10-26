//
//  HellHoundsApp.swift
//  HellHounds
//

import SwiftUI

@main
struct HellHoundsApp: App {
    @State private var store = HoundStore(transport: TransportFactory.makeTransport())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HoundListView(store: store)
        }
        // Stay connected only while in the foreground; the transport reconnects on its own in between.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: store.connect()
            case .background: store.disconnect()
            default: break
            }
        }
    }
}
