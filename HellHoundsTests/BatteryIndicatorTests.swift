//
//  BatteryIndicatorTests.swift
//  HellHoundsTests
//

import Testing
@testable import HellHounds

struct BatteryIndicatorTests {
    @Test(arguments: [
        (nil, BatteryIndicator.Tier.unknown),
        (-1, .unknown),
        (0, .low),
        (20, .low),
        (21, .medium),
        (40, .medium),
        (41, .high),
        (100, .high),
        (104, .high),
    ] as [(Int?, BatteryIndicator.Tier)])
    func tierFollowsTheLevel(level: Int?, tier: BatteryIndicator.Tier) {
        #expect(BatteryIndicator.Tier(level: level) == tier)
    }

    @Test(arguments: [
        (nil, 0.0, "?"),
        (-5, 0.0, "?"),
        (0, 0.0, "0%"),
        (55, 0.55, "55%"),
        (100, 1.0, "100%"),
        (120, 1.0, "120%"),
    ] as [(Int?, Double, String)])
    func fillIsClampedAndLabelShowsTheReading(level: Int?, fill: Double, label: String) {
        #expect(BatteryIndicator.fillFraction(level: level) == fill)
        #expect(BatteryIndicator.label(level: level) == label)
    }
}
