# 0001 — Hell Hounds app founding

- **Status**: accepted
- **Date**: 2026-10-25

## Context

Hell Hounds is an iOS app that controls a homemade set of LED "hellhounds":
LOLIN D1 mini pro V2 boards driving LEDs off a lithium battery pack, talking
MQTT. Each device reports battery level and LED dimmer level and accepts
on/off and dimmer commands. The app dates from 2019 and lives inside the
vendored CocoaMQTT example workspace (`CocoaMQTT-master/Example/Example/`),
next to an unused Objective-C template app at the repo root. It hard-codes
four devices plus a "master" control, uses a single 513-line view controller
with a storyboard, and has a poor-looking battery view. The device firmware
is not currently available; the protocol is known only from the app code.

## Decision

**Goals**

- Clean up the project dramatically: delete the Objective-C template, the
  vendored CocoaMQTT and BatteryView sources and the Podfile; the app lives at
  the repo root; all dependencies via Swift Package Manager.
- Evaluate packages (CocoaMQTT vs. alternatives) and upgrade or replace.
- Make devices flexible and nameable instead of hard-coded.
- Modern UI: scrolls properly, modern tab bar, good battery indicator,
  per-device icons.
- Mock the MQTT devices for manual testing and automation while the real
  devices are off.
- A good README with app screenshots.
- Later: evaluate device firmware capabilities for improvements.
- Stretch: an Android app.

**Constraints and choices**

- Native iOS in **SwiftUI, minimum iOS 26**, using the Liquid Glass design
  language. Observation and SwiftData are available.
- Platform-neutral artifacts so Android can reuse the design later: the MQTT
  protocol is documented in `docs/PROTOCOL.md`, and the device simulator is a
  standalone script, not app code. KMP vs. a separate Android app is decided
  when that phase starts.
- **Broker** stays `broker.hivemq.com:1883` (public, unauthenticated) for now
  because the firmware has it baked in; host, port and topic prefix become
  app settings.
- **Discovery**: subscribe to `HellHounds-MQTT/+/status-json` and show any
  device that reports, rather than a fixed four. The master control applies
  to all discovered devices.
- **Names and images** are stored in the app, keyed by device index now and
  by MAC / chip ID once firmware reports one. Images are an SF Symbol from a
  curated set or an optional photo. Local storage first; iCloud sync once the
  paid Apple Developer membership is active (the iCloud capability needs it).
- **Mocking at two layers**: an in-app fake transport (unit tests, UI tests,
  screenshots) and a Python simulator that acts like N hounds on a real broker.
- **Distribution**: Xcode installs for now; TestFlight for friends and family
  once the developer membership is paid.
- The existing wire protocol is preserved as-is, including its quirks (LED
  "on" is sent as `"0"`).

**Non-goals (for now)**

- Firmware changes (until the device code is in hand).
- App Store release.
- Shared-code (KMP) setup before the Android phase.

## Consequences

- iOS 26 minimum means TestFlight testers need iOS 26 devices; in exchange the
  UI can use current APIs without availability checks.
- Keeping the public broker means anyone who guesses the topic prefix can
  control the lights until a private broker lands with firmware work.
- Index-based device keys are fragile (re-flashing a device with another index
  moves its name); the move to hardware IDs depends on firmware.
- `docs/PROTOCOL.md` and the simulator must be kept in sync with the app's
  protocol code.
