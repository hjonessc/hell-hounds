//
//  HoundProfile.swift
//  HellHounds
//
//  What the user calls a hound and how it looks: a name, an SF Symbol or a
//  photo, kept per broker and hound index (the index is all a hound tells
//  us). Synced through iCloud, so the model follows CloudKit's rules: every
//  property optional or defaulted, no unique constraints.
//

import Foundation
import SwiftData

@Model
final class HoundProfile {
    /// `HoundProfile.brokerKey(for:)` of the broker the hound is on.
    var broker: String = ""
    var houndIndex: Int = 0
    var name: String?
    var symbolName: String?
    @Attribute(.externalStorage) var photoData: Data?
    /// Two devices can create a profile for the same hound while offline;
    /// the newest one wins.
    var modifiedAt: Date = Date.distantPast

    init(broker: String, houndIndex: Int) {
        self.broker = broker
        self.houndIndex = houndIndex
    }

    /// Fake hounds get their own key so test names never land on real ones.
    static let fakeBrokerKey = "fake"

    static func brokerKey(for broker: BrokerAddress, usesFakeTransport: Bool) -> String {
        usesFakeTransport ? fakeBrokerKey : "\(broker.host):\(broker.port)"
    }

    static func predicate(broker: String) -> Predicate<HoundProfile> {
        #Predicate { $0.broker == broker }
    }

    /// The winning profile per hound index among `profiles`.
    static func newestByIndex(_ profiles: [HoundProfile]) -> [Int: HoundProfile] {
        var result: [Int: HoundProfile] = [:]
        for profile in profiles where (result[profile.houndIndex]?.modifiedAt ?? .distantPast) <= profile.modifiedAt {
            result[profile.houndIndex] = profile
        }
        return result
    }
}

/// A hound's look as the card shows it, and as the edit sheet changes it.
struct HoundLook: Equatable {
    var name = ""
    var symbolName: String?
    var photoData: Data?

    static let symbols = [
        "pawprint.fill", "dog.fill", "cat.fill", "hare.fill", "tortoise.fill", "bird.fill",
        "lizard.fill", "fish.fill", "ladybug.fill", "ant.fill", "flame.fill", "bolt.fill",
        "moon.stars.fill", "star.fill", "sparkles", "eye.fill",
    ]
    static let defaultSymbol = "pawprint.fill"

    init(name: String = "", symbolName: String? = nil, photoData: Data? = nil) {
        self.name = name
        self.symbolName = symbolName
        self.photoData = photoData
    }

    init(_ profile: HoundProfile?) {
        self.init(name: profile?.name ?? "", symbolName: profile?.symbolName, photoData: profile?.photoData)
    }

    func title(houndIndex: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hound \(houndIndex + 1)" : trimmed
    }

    var symbol: String { symbolName ?? Self.defaultSymbol }
}

extension ModelContext {
    /// Saves `look` for hound `houndIndex` on `broker`, updating the winning
    /// profile (and dropping losing duplicates) or creating one.
    func saveLook(_ look: HoundLook, broker: String, houndIndex: Int, now: Date = .now) throws {
        let profiles = try fetch(FetchDescriptor(predicate: HoundProfile.predicate(broker: broker)))
            .filter { $0.houndIndex == houndIndex }
        let winner = HoundProfile.newestByIndex(profiles)[houndIndex]
        for profile in profiles where profile !== winner {
            delete(profile)
        }
        let profile = winner ?? HoundProfile(broker: broker, houndIndex: houndIndex)
        if winner == nil { insert(profile) }
        let name = look.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = name.isEmpty ? nil : name
        profile.symbolName = look.symbolName
        profile.photoData = look.photoData
        profile.modifiedAt = now
        try save()
    }
}
