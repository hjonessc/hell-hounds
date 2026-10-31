//
//  EventLogView.swift
//  HellHounds
//
//  The event log, newest first, with hounds shown by their names. Can be
//  filtered to one hound, shared as text, or cleared.
//

import SwiftData
import SwiftUI

struct EventLogView: View {
    let log: EventLog

    @Query private var profiles: [HoundProfile]
    @State private var houndFilter: Int?
    @State private var isConfirmingClear = false

    init(log: EventLog, profileBroker: String) {
        self.log = log
        _profiles = Query(filter: HoundProfile.predicate(broker: profileBroker))
    }

    var body: some View {
        let looks = HoundProfile.newestByIndex(profiles)
        let name = { (index: Int) in HoundLook(looks[index]).title(houndIndex: index) }
        let entries = log.entries.reversed().filter { houndFilter == nil || $0.houndIndex == houndFilter }
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label {
                    if let index = entry.houndIndex {
                        Text("\(Text(name(index)).bold()): \(entry.text)")
                    } else {
                        Text(entry.text)
                    }
                } icon: {
                    Image(systemName: entry.kind.symbol)
                        .foregroundStyle(entry.kind == .warning ? .orange : .secondary)
                }
                .font(.subheadline)
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No Events", systemImage: "list.bullet.rectangle")
            }
        }
        .navigationTitle("Event Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Clear lives here too: a bottom bar would sit under the tab bar.
                Menu("Filter", systemImage: houndFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
                    Picker("Show", selection: $houndFilter) {
                        Text("Everything").tag(Int?.none)
                        ForEach(Set(log.entries.compactMap(\.houndIndex)).sorted(), id: \.self) { index in
                            Text(name(index)).tag(Int?.some(index))
                        }
                    }
                    Divider()
                    Button("Clear Log", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
                        .disabled(log.entries.isEmpty)
                }
                .accessibilityIdentifier("event-log-menu")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.exportText(houndName: name), preview: SharePreview("Hellhounds event log"))
                    .disabled(log.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear the event log?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) { log.clear() }
        }
    }
}

private extension LogEntry.Kind {
    var symbol: String {
        switch self {
        case .connection: "antenna.radiowaves.left.and.right"
        case .found: "pawprint.fill"
        case .received: "arrow.down.circle"
        case .sent: "arrow.up.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .app: "iphone"
        }
    }
}

#Preview {
    let log = EventLog()
    log.add(.connection, "Connected to the broker")
    log.add(.found, "Found: off, 50 %, battery 90 %", houndIndex: 1)
    log.add(.sent, "Switch on (set-state 1)", houndIndex: 1)
    log.add(.warning, "Didn't answer; now offline", houndIndex: 2)
    return NavigationStack { EventLogView(log: log, profileBroker: HoundProfile.fakeBrokerKey) }
        .modelContainer(for: HoundProfile.self, inMemory: true)
}
