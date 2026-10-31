//
//  HelpView.swift
//  HellHounds
//
//  How the app works and what to try when it doesn't, in plain language.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section("How It Works") {
                topic("Phone, server, hounds", systemImage: "point.3.connected.trianglepath.dotted",
                      "Each hound connects to a message server (an MQTT broker) over Wi-Fi. This app connects to the same server. When you flip a switch, the app leaves a message on the server, and the hound picks it up and answers with its state.")
                topic("Finding hounds", systemImage: "pawprint.fill",
                      "When the app connects, it asks hounds 1 to 8 (and any it has seen before) to report. A hound appears as soon as it answers. Hounds don't need to be on the same Wi-Fi as your phone.")
                topic("Names and photos", systemImage: "photo",
                      "Tap a hound's name to give it a name, symbol or photo. These sync to your other devices through iCloud.")
            }

            Section("Tips") {
                topic("Pull down to refresh", systemImage: "arrow.down",
                      "Pull the hound list down to ask every hound to report again, or to reconnect if the app isn't connected.")
                topic("Which hound is which?", systemImage: "light.beacon.max",
                      "Touch and hold a hound's card and choose Identify. It blinks for 30 seconds, then goes back to how it was. Choose Stop Blinking, or use its switch, to stop sooner.")
                topic("Event log", systemImage: "list.bullet.rectangle",
                      "Settings › Event Log lists what the app did and heard, with times. Share it when something went wrong. It stays on this phone.")
            }

            Section("Troubleshooting") {
                topic("\"Not connected\"", systemImage: "antenna.radiowaves.left.and.right.slash",
                      "The app can't reach the server. Check your phone has internet, then tap Retry. The app also keeps retrying on its own.")
                topic("A hound doesn't show up", systemImage: "questionmark.circle",
                      "Make sure it's switched on and charged, and that its Wi-Fi network is working. It can take a few seconds after power-up to connect. Then pull down to refresh.")
                topic("\"Not found\" or \"Offline\"", systemImage: "moon.zzz",
                      "The hound didn't answer the last time the app asked. It may be off, out of Wi-Fi range or out of battery. Pull down to ask again.")
                topic("The switch doesn't do anything", systemImage: "switch.2",
                      "The switch shows what the hound reports, not what you tapped. If it flips back, the hound didn't get the message or didn't answer. Try again, or check the event log.")
                topic("Hounds on another server", systemImage: "server.rack",
                      "Settings › MQTT Broker chooses the server. Hounds only appear on the server their firmware uses, which is normally the public one.")
            }

            Section("Privacy") {
                topic("The public server is shared", systemImage: "eye",
                      "Anyone on the public server who knows where to look can see and switch these hounds. Nothing personal is sent: only on/off, brightness and battery.")
            }
        }
        .navigationTitle("How It Works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func topic(_ title: String, systemImage: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { HelpView() }
}
