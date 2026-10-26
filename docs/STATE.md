# Project state

_Last updated: 2026-10-25 (session 2)_

**Plain language:** Hell Hounds is an iOS app that controls homemade LED
"hellhounds" (D1 mini pro boards on battery) over MQTT. The working app is a
2019-era storyboard app buried in `CocoaMQTT-master/Example/Example/`; this
project cleans it up, rewrites it in SwiftUI for iOS 26, and makes devices
discoverable, nameable and mockable. Requirements and founding decisions:
[ADR 0001](decisions/0001-hell-hounds-founding.md).

---

## Current phase

**Phase 1 — Restructure + simulator: in progress (step 1 of 5 done).**

## Done

- **Session 1 (2026-10-25):** kickoff — requirements, phase plan, ADR 0001.
- **Session 2 (2026-10-25):** Phase 1 step 1 — wrote [PROTOCOL.md](PROTOCOL.md).
  Correction: on the wire `"1"` = LED on and `"0"` = off. ADR 0001 got this
  backwards from the misnamed constants `kMqttLedOn`/`kMqttLedOff`.

## Phased plan

### Phase 1 — Restructure + simulator

Thinnest end-to-end slice: the existing app at the repo root, dead code gone,
the protocol written down, and fake hounds to talk to.

1. ~~Write `docs/PROTOCOL.md`~~ — done (session 2).
2. Write `tools/hound-sim/` — a Python (paho-mqtt) script simulating N hounds
   on a configurable broker/prefix, answering polls and commands, printing
   every state change.
3. Create a new top-level Xcode project (`HellHounds.xcodeproj`, Swift,
   iOS 26) and move `ViewController.swift`, `BatteryView.swift`,
   `AppDelegate.swift`, `Main.storyboard`, `LaunchScreen.storyboard` and the
   app icon from `Assets/` into it; add CocoaMQTT via SPM.
4. Delete the Objective-C `HellHounds/`, `HellHoundsTests/`,
   `CocoaMQTT-master/` (incl. `BatteryView-master/`, Podfile, workspaces) and
   unused `Assets/` zips/images. Resolve Q6 for `client-keycert.p12`.
5. Build, run in Simulator, connect, check against `hound-sim`.

**Done when:** a clean clone builds the top-level project in Xcode; the
unchanged UI connects to the broker, shows 4 simulated hounds from the
script, and toggling or dimming one is visible in the script's output.

### Phase 2 — MQTT layer + package review

ADR on keeping CocoaMQTT vs. alternatives (e.g. MQTTNIO). Extract a transport
protocol and an `@Observable` device model out of the view controller; add an
in-app fake transport.

**Done when:** the ADR is written, and unit tests on the fake transport cover
the status / set-state / set-level round trip and pass with `xcodebuild test`.

### Phase 3 — SwiftUI rewrite

Device list with wildcard discovery, master control, a new battery indicator,
broker settings, Liquid Glass tab bar and styling, proper scrolling.

**Done when:** a UI test on the fake transport passes with 6 devices (more than
fit on screen), and the app works against `hound-sim`, including a 5th device
appearing without code changes.

### Phase 4 — Names and images

Rename devices, pick an SF Symbol or photo, persisted locally (SwiftData);
iCloud sync once the developer membership is paid (Q4).

**Done when:** a renamed device with a photo keeps both after relaunch
(covered by a test).

### Phase 5 — README

README with screenshots generated from UI tests on the fake transport.

**Done when:** the README renders on GitHub with current screenshots, and one
command regenerates them.

### Phase 6 — TestFlight

Signing, bundle ID, privacy text, first build out. Blocked on Q4.

**Done when:** a friend installs the app from TestFlight.

### Phase 7 — Device evaluation

Review the D1 mini pro firmware; propose improvements (unique ID,
device-reported names, retained status + LWT, private broker). Blocked on Q1.

**Done when:** an ADR on firmware improvements is accepted.

### Phase 8 — Android (stretch)

Decide KMP vs. separate app (Q5), then build it against `docs/PROTOCOL.md`.

**Done when:** the Android app controls simulated hounds through the same
protocol.

## Open questions

- **Q1** (blocks Phase 7): What can the firmware do? Waiting on the device
  code; assumed to be based on the board's MQTT sample code.
- **Q2** (affects Phase 3): Do devices publish status on their own, or only in
  response to `msg`? Today the app polls each index. If poll-only, discovery
  falls back to probing indices 0..N.
- **Q3** (blocks Phase 7): Move to a private / authenticated broker?
- **Q4** (blocks iCloud in Phase 4, and Phase 6): When to pay for the Apple
  Developer membership — user will pay once it becomes useful.
- **Q5** (blocks Phase 8): KMP vs. separate Android app.
- **Q6** (Phase 1): What is `CocoaMQTT-master/Example/Example/client-keycert.p12`
  and is it secret? It's committed to git and the loader is never called.

## Known issues

_None yet._

## Next steps

1. Phase 1 step 2: write `tools/hound-sim/` against [PROTOCOL.md](PROTOCOL.md).
   Until Q2 is answered, the sim should send `status-json` after every
   command as well as when polled, so the old app (which polls only once)
   shows changes.
