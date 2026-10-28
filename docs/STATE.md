# Project state

_Last updated: 2026-10-27 (session 5)_

**Plain language:** Hell Hounds is an iOS app that controls homemade LED
"hellhounds" (D1 mini pro boards on battery) over MQTT. The working app is a
2019-era storyboard app (now at the repo root in `HellHounds/`); this
project cleans it up, rewrites it in SwiftUI for iOS 26, and makes devices
discoverable, nameable and mockable. Requirements and founding decisions:
[ADR 0001](decisions/0001-hell-hounds-founding.md).

---

## Current phase

**Phase 1 — Restructure + simulator: done (session 2).**
**Phase 2 — MQTT layer + package review: done (session 3).**
**Phase 3 — SwiftUI rewrite: done (session 4).**
**Phase 4 — Names and images: not started (skipped for now).**
**Phase 5 — README: not started (skipped for now).**
**Phase 6 — TestFlight: done (session 5).** Taken ahead of Phases 4–5 once
the user paid for the Apple Developer membership (Q4).

## Done

- **Sessions 1–2 (2026-10-25), kickoff + Phase 1:** requirements and ADR 0001;
  PROTOCOL.md (on the wire `"1"` = on, `"0"` = off, correcting ADR 0001),
  `tools/hound-sim/`, the top-level Xcode project, leftovers deleted, clean
  clone checked against the sim — see tag `m1` and git history for detail.
- **Session 3 (2026-10-26):** Phase 2 step 1 — researched MQTT libraries and
  wrote [ADR 0002](decisions/0002-mqtt-client-library.md):
  switch to MQTTNIO 3 (pin `3.0.0-rc.1`) behind our own `MQTTTransport`
  protocol, with CocoaMQTT 2.4.1 as the fallback.
  User accepted it. Phase 2 step 2 — pulled the protocol out of
  `ViewController.swift`: `MQTTTransport` (events as an `AsyncStream`),
  `HoundProtocol` (topics, payloads, tolerant `status-json` parsing),
  `@Observable HoundStore`, and an interim `CocoaMQTTTransport` adapter. The
  view controller now redraws through UIKit's `updateProperties()`
  observation tracking. Checked in Simulator against `hound-sim --escaped`:
  4 hounds with the right batteries, a switch (`set-state 1`), a slider
  (`set-level 92`), the Master slider (`set-level 81` to all four) and the Master
  switch (`set-state 0` to all four), with the cards updating from the returned status.
  Phase 2 step 3 — `MQTTNIOTransport` (MQTTNIO `3.0.0-rc.1` plus `NIOCore` /
  `NIOTransportServices`; CocoaMQTT package and adapter removed; reconnect
  loop with 1–30 s backoff; disconnect on background, reconnect on
  foreground). The app takes `-mqttHost` / `-mqttPort` launch arguments for a
  local broker (see `tools/hound-sim/README.md`). Checked on local Mosquitto
  with `hound-sim --escaped`: 4 hounds, switch (`set-state 1`), slider
  (`set-level 88`), Master switch (`set-state 0` to all four), reconnect after
  a broker restart and after a trip to the background, plus a 150 ms delay
  proxy. A "subscription bug" reported mid-session was a misread screenshot
  (pixel check: no card was ever dimmed). While testing on the public broker a
  **real hound 1 was live** and got test commands; it was turned back off
  (`set-state 0`, confirmed by its status). Its level is still 81 from a test;
  the original level isn't known. See PROTOCOL.md "Seen from a real hound".
  Phase 2 step 4 — `FakeMQTTTransport` in the app (in-process hounds that
  answer like the real firmware: boolean `ledState`, status after a poll and
  after every command, `reportsStatusAfterCommands` to switch that off for
  Q2), a `HellHoundsTests` unit-test target (Swift Testing, hosted by the
  app) and a shared `HellHounds` scheme. 25 tests: protocol topics/payloads,
  status parsing, topic-filter matching, and `HoundStore` round trips
  (status, set-state, set-level, master, drop + reconnect, poll-only
  hounds). Swapping the on/off payload makes 11 of them fail, as it should.
  The app uses the fake transport when hosting tests or launched with
  `-useFakeTransport YES`; the test run made no network connections.
  **Phase 2 done.**
- **Session 4 (2026-10-26/27):** Phase 3 step 1 — the app is SwiftUI now:
  `HellHoundsApp` owns the `HoundStore`, connects when the scene is active
  and disconnects in the background (`scenePhase`); `TransportFactory` keeps
  the launch-argument rules. An interim plain `HoundListView` (master row plus
  one row per hound; slider sends on release). Deleted the storyboards,
  `AppDelegate`, `ViewController`, the UIKit `BatteryView` and every image
  set except the app icon; generated launch screen and scene manifest.
  Swift 6 language mode on for both targets (no warnings). 25 tests pass.
  Checked `-useFakeTransport YES` (4 hounds, batteries 100/70/40/10) and,
  on local Mosquitto with `hound-sim --escaped`: slider (`set-level 84`),
  a switch (`set-state 0`), master switch (`set-state 1` to all four), the
  rows matching the returned status (pixel check), and a disconnect in the
  background with reconnect and re-poll on return.
  Phase 3 step 2 — discovery: `HoundStore` starts empty, subscribes to
  `HellHounds-MQTT/+/status-json` and adds a hound (sorted by index) the
  first time it reports; every connect polls the probe range 0..<8 plus the
  indices already seen. `statusIndex` accepts digits only (rejects `-1`,
  `+1`, empty). `-fakeHoundCount N` sets the fake's hound count (batteries
  spread 100→10 like `hound-sim`). 30 tests (new: discovery, ordering,
  out-of-range self-reporter, malformed topics); removing the digits-only
  check fails two of them. Checked on local Mosquitto: `hound-sim -n 5`
  shows 5 hounds with the sim's batteries; a sim started at index 11 while
  the app was connected appeared as "Hound 12" and got `set-state 1` from
  its switch. `-useFakeTransport YES -fakeHoundCount 6` shows 6.
  Phase 3 step 3 — cards: `HoundListView` is a scroll view of dark
  blood-red cards (master "All Hounds" on top, then one per hound), each
  with a switch, a send-on-release slider with its percentage, and the new
  SwiftUI `BatteryIndicator` (red ≤ 20, yellow ≤ 40, green above, "?" when
  unknown; 2 tests). A banner shows "Connecting…" or "Not connected" with a
  Retry button; an empty state shows when connected with no hounds.
  Accessibility IDs: `hound-<index>` / `hound-master` plus `-toggle` and
  `-slider`, and `connection-banner`. With 6 hounds the 6th is off screen.
  Fixed in `MQTTNIOTransport`: `connect()` during the backoff wait now
  retries immediately (it used to do nothing while the store showed
  "Connecting…"); checked by timing against Mosquitto (connected 0.6 s
  after the tap, 6 s before the natural retry). Checked light and dark.
  Phase 3 step 4 — Settings and Liquid Glass: a `TabView` (Hounds,
  Settings) with the iOS 26 floating tab bar (minimizes on scroll); the
  connection banner uses `glassEffect`. `AppModel` owns the broker and the
  `HoundStore`; changing the broker saves it (`brokerHost` / `brokerPort`
  in UserDefaults) and replaces the store. `-mqttHost` or the fake
  transport lock the broker (Settings fields disabled), so test runs can't
  be switched to the public broker. MQTTNIO connect timeout 10 s → 5 s.
  8 new tests (`BrokerAddress` parsing, launch args, `AppModel`
  switching); 40 in all. Checked with two local brokers (1883 with 2
  sim hounds, 1884 with 3): the stored broker was used at launch, switching
  the port in Settings left A and polled B's 3 hounds, and a relaunch
  without arguments went straight to B.
  Phase 3 step 5 — `HellHoundsUITests` target (XCTest UI tests, in the
  shared scheme, so the usual `xcodebuild test` command runs them too).
  Every launch passes `-useFakeTransport YES`. Two tests: 6 fake hounds,
  the 6th starts off screen, swipe until it's hittable, flip it and wait for
  the fake's status to turn it on (others unchanged); and Settings can't
  change the broker on the fake transport. Both fail when the switch is
  wired to the wrong hound or the broker lock is removed. UI tests take
  about 16 s.
  Phase 3 step 6 — on local Mosquitto with `hound-sim -n 5`: 5 cards with
  the sim's batteries (100/78/55/32/10); Hound 3's switch (`set-state 1` to
  hound 2), Hound 2's slider (`set-level 92` to hound 1), the master slider
  (`set-level 17` to all five) and the master switch (`set-state 0`, then
  `set-state 1`, to all five), with the cards following the returned status.
  Scrolled to the end, Hound 5 clears the tab bar. **Phase 3 done.**

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

1. ~~ADR 0002 (MQTTNIO 3)~~ — done (session 3).
2. ~~`MQTTTransport` + `@Observable HoundStore` out of the view controller~~ — done (session 3).
3. ~~`MQTTNIOTransport` with reconnect; CocoaMQTT removed~~ — done (session 3).
4. ~~Fake transport, test target, round-trip unit tests~~ — done (session 3).

**Done when:** the ADR is written, and unit tests on the fake transport cover
the status / set-state / set-level round trip and pass with `xcodebuild test`.

### Phase 3 — SwiftUI rewrite

Device list with wildcard discovery, master control, a new battery indicator,
broker settings, Liquid Glass tab bar and styling, proper scrolling.

1. ~~SwiftUI `App` + interim list; UIKit, storyboards and old assets gone; Swift 6 mode~~ — done (session 4).
2. ~~Discovery in `HoundStore` (wildcard, probe range 0..<8)~~ — done (session 4).
3. ~~Device list cards, connection banner, `BatteryIndicator`~~ — done (session 4).
4. ~~Settings tab, `AppModel`, `TabView` with Liquid Glass~~ — done (session 4).
5. ~~UI test target: 6 fake hounds, scroll to the 6th, toggle it~~ — done (session 4).
6. ~~Manual check on local Mosquitto with `hound-sim -n 5`~~ — done (session 4).

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

Signing, bundle ID, privacy text, first build out.

1. ~~Inputs from the user~~ — done (session 5): team `K4BXBW45T2` is the
   paid team; bundle ID `io.henryerinjones.HellHounds`; the friend is an
   **internal** tester (an App Store Connect user, so no Beta App Review);
   a fresh install defaults to the **public broker** (real hounds), as now.
2. ~~Identity~~ — done (session 5): app bundle ID is now
   `io.henryerinjones.HellHounds` (was `ChatExample`; installs of the old
   ID don't update in place). Display name "Hellhounds", version 1.0 (1).
3. ~~Compliance~~ — done (session 5): `HellHounds/PrivacyInfo.xcprivacy`
   (no tracking, no data collected, UserDefaults with reason CA92.1);
   `ITSAppUsesNonExemptEncryption = NO` (plain TCP MQTT);
   `NSLocalNetworkUsageDescription` for LAN brokers; app icon PNGs
   re-encoded without an alpha channel (they were already fully opaque).
   Checked in the built bundle. 40 unit + 2 UI tests pass.
4. ~~Real-device run~~ — done (session 5): the user signed Xcode in to the
   paid account; `xcodebuild build -allowProvisioningUpdates` for the
   iPhone 14 Pro (`00008120-0012425811E3C01E`) made the development
   certificate and profile; installed with `devicectl device install app`
   and launched with `devicectl device process launch --device <id>
   --terminate-existing io.henryerinjones.HellHounds -- -useFakeTransport
   YES` (app arguments go after `--`). Screenshot
   (`devicectl device capture screenshot --destination …`, read by OCR):
   All Hounds plus Hounds 1–4 with the fake's batteries 100/70/40/10, no
   banner. Not checked on the phone: touching a control, or the public or a
   LAN broker.
5. ~~App Store Connect record, archive and upload~~ — done (session 5):
   the user registered the explicit App ID `io.henryerinjones.HellHounds`
   in the developer portal (the device build had used the team wildcard,
   so App Store Connect didn't offer it) and created the app record (SKU
   is the user's choice). Version 1.0 build 1 archived and uploaded with
   [`tools/testflight/ExportOptions.plist`](../tools/testflight/ExportOptions.plist)
   (commands under "Uploading a TestFlight build" below). Apple's
   processing of the build wasn't watched.
6. ~~Testers~~ — done (session 5): build 1.0 (1) is "Testing" in the
   internal group "All" with the user and one friend (both App Store
   Connect users); both installed from TestFlight. Tip: the TestFlight
   invites went to the spam folder.

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
- **Q2** (affected Phase 3; handled by polling): Do devices publish status on their own, or only in
  response to `msg`? Partly answered 2026-10-26: a real hound published
  `status-json` (plus `status` and `BatStats`) right after `set-state`. Still unknown: whether hounds report at boot or on a
  timer. The app subscribes to `+/status-json` and polls indices 0–7 plus
  every index seen, once per connect, so either answer works.
- **Q3** (blocks Phase 7): Move to a private / authenticated broker?
- ~~**Q4**~~ answered (session 5): the user has the paid Apple Developer
  membership. Unblocks Phase 6 and iCloud sync in Phase 4.
- **Q5** (blocks Phase 8): KMP vs. separate Android app.
- ~~**Q6**~~ answered (session 2): `client-keycert.p12` is the CocoaMQTT
  example's sample client cert (`CN=MacBook-Air.local, O=client`, issued by
  `MyTestCA`, password `MySecretPassword`), committed with the vendored
  library in 2019. Not secret, never loaded (the app uses plain TCP). Deleted
  in Phase 1 step 4; no history rewrite needed.

## Known issues

- **Real hounds are live on the public broker** (index 1 at least, 2026-10-26).
  Never drive the app or `hound-sim` on the public broker for testing; use
  local Mosquitto (`tools/hound-sim/README.md`). Real hound 1's level is
  still 81 from a session 3 test; its earlier level isn't known.
- Screenshot checks by the image inspector can be wrong (it reported dimmed
  cards that weren't). Confirm UI state with a pixel measurement or the
  sim/broker log before acting on it.
- Testing tip: in the iOS Simulator tool a tap doesn't flip a switch; drag
  the thumb with `duration` ≥ 0.5 s (a quick 0.3 s drag was ignored once).
  Sliders need a drag too and send on release. Launch with
  `xcrun simctl launch <id> io.henryerinjones.HellHounds -mqttHost localhost`.
- `check_sim.py` uses a random prefix and is safe.
- On MQTTNIO / NIOTransportServices a refused connection (no broker) fails
  only at the connect timeout (now 5 s), so "Connecting…" shows that long.
- **The bundle ID changed (session 5), so the Simulator's
  `io.henryerinjones.HellHounds` app has no saved broker: launching it
  without `-mqttHost` or `-useFakeTransport YES` connects to the public
  broker with real hounds.** Always pass one of them. (The old
  `ChatExample` app in the Simulator still has `localhost:1884` saved.)
  Saved values don't show in `simctl spawn … defaults read`.
- Simulator tool: after `select_all` in a text field, an edit menu covers
  the row below; press the right-arrow key to dismiss it before tapping.
- The tab bar's minimize-on-scroll (`.tabBarMinimizeBehavior(.onScrollDown)`)
  wasn't seen to minimize in the short lists tested; not investigated.
- MQTTNIO is still pinned to `3.0.0-rc.1` (ADR 0002).

## Next steps

1. **Start Phase 4 (names and images)** with a short plan. iCloud sync is
   unblocked now (Q4). A SwiftData
   model keyed by broker + hound index (a name, an SF Symbol or a photo),
   because the index is all a hound tells us (Q1, Phase 7 may add a unique
   ID). Rename and pick an icon from the card, show the name instead of
   "Hound n", photos stored as external data. iCloud sync waits for Q4.
   **Done when** a renamed device with a photo keeps both after relaunch
   (covered by a test).
2. Move MQTTNIO from `3.0.0-rc.1` to `3.0.0` once it's tagged (separate commit).

Manual testing: start Docker Desktop, then the local broker and sim as in
`tools/hound-sim/README.md`, and launch with `-mqttHost localhost`. Never on
the public broker.

Running the tests (use the simulator's ID; matching by name didn't resolve
here, and without `-collect-test-diagnostics never` a failing run waits
600 s gathering simulator diagnostics):

```bash
xcodebuild test -project HellHounds.xcodeproj -scheme HellHounds -destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)" -collect-test-diagnostics never
```

Uploading a TestFlight build (bump `CURRENT_PROJECT_VERSION` in both app
configurations first; build 1 is used):

```bash
xcodebuild archive -project HellHounds.xcodeproj -scheme HellHounds -configuration Release -destination "generic/platform=iOS" -archivePath build/HellHounds.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/HellHounds.xcarchive -exportOptionsPlist tools/testflight/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

Notes for later phases:
- Real hounds also publish `status` and `BatStats` (voltage and current);
  the Phase 3 battery indicator could use them (PROTOCOL.md).
- The project was generated once with XcodeGen and is now edited in Xcode
  (session 3 added the test target and shared scheme by editing the project
  file directly); there's no `project.yml` to keep in sync.
