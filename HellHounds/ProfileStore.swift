//
//  ProfileStore.swift
//  HellHounds
//
//  Where hound profiles are kept: iCloud for real hounds, a local store for
//  the fake transport (UI and unit tests), so test data never syncs.
//

import Foundation
import OSLog
import SwiftData

enum ProfileStore {
    static let cloudKitContainer = "iCloud.io.henryerinjones.HellHounds"

    private static let logger = Logger(subsystem: "io.henryerinjones.HellHounds", category: "ProfileStore")

    /// Launch arguments, read through UserDefaults:
    /// - `-resetProfiles YES`: start the fake transport's store empty (UI tests).
    static func makeContainer(usesFakeTransport: Bool = TransportFactory.usesFakeTransport) -> ModelContainer {
        let schema = Schema([HoundProfile.self])
        if usesFakeTransport {
            // Its own folder, so a reset also removes the SQLite side files and external photos.
            let folder = URL.applicationSupportDirectory.appending(path: "FakeProfiles", directoryHint: .isDirectory)
            if UserDefaults.standard.bool(forKey: "resetProfiles") {
                try? FileManager.default.removeItem(at: folder)
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "Profiles.store")
            return container(schema, ModelConfiguration("FakeProfiles", schema: schema, url: url, cloudKitDatabase: .none))
        }
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration("Profiles", schema: schema, cloudKitDatabase: .private(cloudKitContainer))
            )
        } catch {
            // Names still work without iCloud; they just stay on this device.
            logger.error("CloudKit store failed, using a local one: \(error)")
            return container(schema, ModelConfiguration("LocalProfiles", schema: schema, cloudKitDatabase: .none))
        }
    }

    private static func container(_ schema: Schema, _ configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            logger.error("Profile store failed, keeping profiles in memory: \(error)")
            // An in-memory store can't fail to open.
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
    }
}
