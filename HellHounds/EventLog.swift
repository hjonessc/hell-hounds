//
//  EventLog.swift
//  HellHounds
//
//  What the app did and heard, for troubleshooting: connections, hounds
//  found, commands sent and status received. Kept in a file on this phone
//  only (not synced, not backed up), newest `capacity` entries.
//

import Foundation
import Observation

struct LogEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case connection, found, received, sent, warning, app
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    /// The hound it's about, shown by its name; nil for app-wide events.
    let houndIndex: Int?
    let text: String
}

@MainActor
@Observable
final class EventLog {
    /// Oldest first.
    private(set) var entries: [LogEntry] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// With no `fileURL` the log lives in memory only (tests, previews).
    init(fileURL: URL? = nil, capacity: Int = 1000, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.capacity = capacity
        self.now = now
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([LogEntry].self, from: data) {
            entries = Array(saved.suffix(capacity))
        }
    }

    /// `Application Support/event-log.json`.
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "event-log.json")
    }

    func add(_ kind: LogEntry.Kind, _ text: String, houndIndex: Int? = nil) {
        entries.append(LogEntry(date: now(), kind: kind, houndIndex: houndIndex, text: text))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        scheduleSave()
    }

    func clear() {
        entries = []
        scheduleSave()
    }

    /// The log as plain text, oldest first, for sharing.
    func exportText(houndName: (Int) -> String) -> String {
        entries.map { entry in
            let time = entry.date.formatted(date: .abbreviated, time: .standard)
            let hound = entry.houndIndex.map { "\(houndName($0)): " } ?? ""
            return "\(time)  [\(entry.kind.rawValue)] \(hound)\(entry.text)"
        }
        .joined(separator: "\n")
    }

    /// Writes at most once a second, however busy the hounds are.
    private func scheduleSave() {
        guard fileURL != nil, saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.save()
        }
    }

    private func save() {
        saveTask = nil
        guard var fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? fileURL.setResourceValues(values)
    }
}

extension Date {
    /// "10:42:13 PM (5m 3s ago)", with the date instead when it isn't today.
    func timeAndAge(now: Date) -> String {
        let time = Calendar.current.isDate(self, inSameDayAs: now)
            ? formatted(date: .omitted, time: .standard)
            : formatted(date: .abbreviated, time: .shortened)
        let seconds = max(0, Int(now.timeIntervalSince(self)))
        let age = Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
        return "\(time) (\(age) ago)"
    }
}
