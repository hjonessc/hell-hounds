//
//  EventLogTests.swift
//  HellHoundsTests
//
//  The event log keeps the newest entries and survives a relaunch.
//

import Foundation
import Testing
@testable import HellHounds

@MainActor
struct EventLogTests {
    @Test func keepsOnlyTheNewestEntries() {
        let log = EventLog(capacity: 3)
        for n in 1...5 {
            log.add(.app, "event \(n)")
        }
        #expect(log.entries.map(\.text) == ["event 3", "event 4", "event 5"])
    }

    @Test func survivesReopening() async throws {
        let url = URL.temporaryDirectory.appending(path: "event-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = EventLog(fileURL: url)
        log.add(.found, "Found: on", houndIndex: 2)
        log.add(.connection, "Disconnected")

        let deadline = ContinuousClock.now + .seconds(3)
        while !FileManager.default.fileExists(atPath: url.path()) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let reopened = EventLog(fileURL: url)
        #expect(reopened.entries == log.entries)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func exportNamesHoundsAndGivesReadableTimes() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let log = EventLog(now: { date })
        log.add(.sent, "Switch on (set-state 1)", houndIndex: 0)
        log.add(.app, "App started")
        let time = date.formatted(date: .abbreviated, time: .standard)
        #expect(log.exportText(houndName: { "Hound \($0 + 1)" }) == """
            \(time)  [sent] Hound 1: Switch on (set-state 1)
            \(time)  [app] App started
            """)
    }
}
