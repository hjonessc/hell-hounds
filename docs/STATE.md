# Project state

_Last updated: 2026-10-26 (session 2)_

**Plain language:** Hell Hounds is an iOS app that controls homemade LED
"hellhounds" (D1 mini pro boards on battery) over MQTT. The working app is a
2019-era storyboard app (now at the repo root in `HellHounds/`); this
project cleans it up, rewrites it in SwiftUI for iOS 26, and makes devices
discoverable, nameable and mockable. Requirements and founding decisions:
[ADR 0001](decisions/0001-hell-hounds-founding.md).

---

## Current phase

**Phase 1 — Restructure + simulator: done (session 2).**
**Phase 2 — MQTT layer + package review: not started.**

## Done

- **Session 1 (2026-10-25):** kickoff — requirements, phase plan, ADR 0001.
- **Session 2 (2026-10-25):** Phase 1 step 1 — wrote [PROTOCOL.md](PROTOCOL.md).
  Correction: on the wire `"1"` = LED on and `"0"` = off. ADR 0001 got this
  backwards from the misnamed constants `kMqttLedOn`/`kMqttLedOff`.
  Phase 1 step 2 — wrote [`tools/hound-sim/`](../tools/hound-sim/README.md)
  (simulator plus `check_sim.py` smoke test, passing against the public broker).
  Phase 1 step 3 — new top-level `HellHounds.xcodeproj` (iOS 26, Swift 5 mode,
  CocoaMQTT 2.1.6 via SPM, synchronized `HellHounds/` folder, generated
  Info.plist); app files moved there with `git mv`. The Objective-C template
  project had to go first because it used the same names. Simulator build
  passes; checked in Simulator against `hound-sim`: 4 hounds shown with
  the right batteries, the switch sends `set-state 1`, the slider sends
  `set-level`, and the switch and Master card update from the returned status.
  Phase 1 step 4 — deleted `HellHoundsTests/`, `CocoaMQTT-master/` (vendored
  library, BatteryView source, Podfile, old project, `client-keycert.p12`) and
  `Assets/` (copies of the app icon and unused source images). Fixed a startup
  race in `check_sim.py` (it now polls until the sim answers).
  Phase 1 step 5 — a fresh clone of `f8d6d1b` builds; its app, run against
  `hound-sim`, shows the 4 hounds, and the sim logged a switch (`set-state 1`),
  a slider (`set-level 14`) and the Master switch (`set-state 0` to all four).
  **Phase 1 done.**

## Phased plan

### Phase 1 — Restructure + simulator

Thinnest end-to-end slice: the existing app at the repo root, dead code gone,
the protocol written down, and fake hounds to talk to.

1. ~~Write `docs/PROTOCOL.md`~~ — done (session 2).
2. ~~Write `tools/hound-sim/`~~ — done (session 2).
3. ~~Create the top-level Xcode project and move the app in~~ — done (session 2).
4. ~~Delete the leftovers~~ — done (session 2).
5. ~~Build from a clean clone and check against `hound-sim`~~ — done (session 2).

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
- ~~**Q6**~~ answered (session 2): `client-keycert.p12` is the CocoaMQTT
  example's sample client cert (`CN=MacBook-Air.local, O=client`, issued by
  `MyTestCA`, password `MySecretPassword`), committed with the vendored
  library in 2019. Not secret, never loaded (the app uses plain TCP). Delete it
  in step 4; no history rewrite needed.

## Known issues

- The old app crashes on a `status-json` missing `ledLvl` or `battery` (force
  unwrap in `ViewController.swift`); fix when the model moves out in Phase 2.
- Testing tip: in the iOS Simulator tool a tap doesn't toggle a `UISwitch`;
  drag the thumb instead (sliders need a drag too, and send on release).
- `hound-sim` on the default prefix also controls any real hounds that are on;
  `check_sim.py` uses a random prefix and is safe.

## Next steps

1. Phase 2: research CocoaMQTT 2.x vs. alternatives (e.g. MQTTNIO) for iOS 26
   and Swift 6 concurrency, and write ADR 0002.
2. Then pull a transport protocol and an `@Observable` device model out of
   `ViewController.swift`, add an in-app fake transport, and add unit tests
   for the status / set-state / set-level round trip (`xcodebuild test`).

Notes for later phases:
- Bundle ID is still `io.henryerinjones.ChatExample` (kept so existing installs
  update in place); change it in Phase 6.
- The storyboard still has the CocoaMQTT example's chat tabs
  (`ChatViewController` etc., classes that don't exist); `viewDidLoad` removes
  them at runtime. They go away with the Phase 3 rewrite.
- The project was generated once with XcodeGen and is now edited in Xcode;
  there's no `project.yml` to keep in sync.
