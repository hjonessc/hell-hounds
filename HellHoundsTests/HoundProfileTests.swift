//
//  HoundProfileTests.swift
//  HellHoundsTests
//
//  Names, symbols and photos: kept per broker and hound, surviving a
//  reopened store, with duplicates from two devices resolved.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import HellHounds

@MainActor
struct HoundProfileTests {
    let storeURL = URL.temporaryDirectory.appending(path: "HoundProfileTests-\(UUID().uuidString).store")

    private func openStore() throws -> ModelContainer {
        let schema = Schema([HoundProfile.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none))
    }

    private func profiles(in container: ModelContainer) throws -> [HoundProfile] {
        try container.mainContext.fetch(FetchDescriptor<HoundProfile>())
    }

    /// Phase 4's "done when": a renamed hound with a photo keeps both after relaunch.
    @Test func nameAndPhotoSurviveReopeningTheStore() throws {
        let photo = Data(repeating: 0xAB, count: 200_000)  // big enough for external storage
        do {
            let container = try openStore()
            try container.mainContext.saveLook(HoundLook(name: " Cerberus ", photoData: photo), broker: "localhost:1883", houndIndex: 2)
        }

        let reopened = try openStore()
        let saved = try profiles(in: reopened)
        #expect(saved.count == 1)
        #expect(saved.first?.broker == "localhost:1883")
        #expect(saved.first?.houndIndex == 2)
        #expect(saved.first?.name == "Cerberus")
        #expect(saved.first?.photoData == photo)
        #expect(HoundLook(saved.first).title(houndIndex: 2) == "Cerberus")
    }

    @Test func savingUpdatesTheProfileInsteadOfAddingOne() throws {
        let container = try openStore()
        let context = container.mainContext
        try context.saveLook(HoundLook(name: "Rex", symbolName: "flame.fill"), broker: "b", houndIndex: 0)
        try context.saveLook(HoundLook(name: "Rex II"), broker: "b", houndIndex: 0)
        try context.saveLook(HoundLook(name: "Other broker"), broker: "c", houndIndex: 0)

        let onB = try context.fetch(FetchDescriptor(predicate: HoundProfile.predicate(broker: "b")))
        #expect(onB.count == 1)
        #expect(onB.first?.name == "Rex II")
        #expect(onB.first?.symbolName == nil)
        #expect(try profiles(in: container).count == 2)
    }

    /// Two devices named the same hound offline; iCloud delivered both.
    @Test func newestDuplicateWinsAndSavingDropsTheOthers() throws {
        let container = try openStore()
        let context = container.mainContext
        for (name, seconds) in [("Old", 10.0), ("New", 30.0), ("Middle", 20.0)] {
            let profile = HoundProfile(broker: "b", houndIndex: 1)
            profile.name = name
            profile.modifiedAt = Date(timeIntervalSince1970: seconds)
            context.insert(profile)
        }
        try context.save()

        #expect(HoundProfile.newestByIndex(try profiles(in: container))[1]?.name == "New")

        try context.saveLook(HoundLook(name: "Final"), broker: "b", houndIndex: 1)
        let left = try profiles(in: container)
        #expect(left.map(\.name) == ["Final"])
    }

    @Test func emptyNameFallsBackToTheIndex() {
        #expect(HoundLook().title(houndIndex: 4) == "Hound 5")
        #expect(HoundLook(name: "   ").title(houndIndex: 0) == "Hound 1")
        #expect(HoundLook().symbol == HoundLook.defaultSymbol)
    }

    @Test func fakeHoundsHaveTheirOwnBrokerKey() throws {
        let broker = try #require(BrokerAddress(host: "localhost", port: 1884))
        #expect(HoundProfile.brokerKey(for: broker, usesFakeTransport: false) == "localhost:1884")
        #expect(HoundProfile.brokerKey(for: broker, usesFakeTransport: true) == HoundProfile.fakeBrokerKey)
        #expect(HoundProfile.brokerKey(for: .publicBroker, usesFakeTransport: true) == HoundProfile.fakeBrokerKey)
    }

    @Test func photosAreDownscaledForSync() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let jpeg = try #require(await HoundEditSheet.downscaledJPEG(big))
        let image = try #require(UIImage(data: jpeg))
        #expect(image.size == CGSize(width: 512, height: 256))
    }
}
