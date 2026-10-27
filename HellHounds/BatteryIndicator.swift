//
//  BatteryIndicator.swift
//  HellHounds
//
//  A horizontal battery with a fill and the percentage beside it. Replaces
//  the 2019 UIKit BatteryView (red at 20 % or less, grey "?" when unknown).
//

import SwiftUI

struct BatteryIndicator: View {
    /// 0...100, or nil when the hound hasn't reported.
    let level: Int?

    enum Tier: Equatable {
        case unknown, low, medium, high

        init(level: Int?) {
            switch level {
            case .some(0...20): self = .low
            case .some(21...40): self = .medium
            case .some(41...): self = .high  // over 100 can happen while charging
            default: self = .unknown
            }
        }

        var color: Color {
            switch self {
            case .unknown: .gray
            case .low: .red
            case .medium: .yellow
            case .high: .green
            }
        }
    }

    private var tier: Tier { Tier(level: level) }

    /// The text beside the battery: "?" when unknown.
    static func label(level: Int?) -> String {
        guard let level, Tier(level: level) != .unknown else { return "?" }
        return "\(level)%"
    }

    /// The filled fraction of the body, clamped to 0...1.
    static func fillFraction(level: Int?) -> Double {
        guard let level else { return 0 }
        return Double(min(max(level, 0), 100)) / 100
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.label(level: level))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.secondary, lineWidth: 1.5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(tier.color)
                                .frame(width: (geometry.size.width - 6) * Self.fillFraction(level: level))
                                .padding(3)
                        }
                    }
                    .frame(width: 30, height: 15)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.secondary)
                    .frame(width: 2.5, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(tier == .unknown ? "Unknown" : "\(level ?? 0) percent")
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 12) {
        ForEach([nil, 0, 10, 20, 21, 40, 41, 70, 100], id: \.self) { level in
            BatteryIndicator(level: level)
        }
    }
    .padding()
}
