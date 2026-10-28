# Project state

_Last updated: 2026-10-27 (session 6)_

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
**Phase 4 — Names and images: in progress (session 6).**
**Phase 5 — README: not started (skipped for now).**
**Phase 6 — TestFlight: done (session 5).** Taken ahead of Phases 4–5 once
the user paid for the Apple Developer membership (Q4).

## Done

- **Sessions 1–2 (2026-10-25), kickoff + Phase 1:** requirements and ADR 0001;
  PROTOCOL.md (on the wire `"1"` = on, `"0"` = off, correcting ADR 0001),
  `tools/hound-sim/`, the top-level Xcode project, leftovers deleted, clean
  clone checked against the sim — see tag `m1` and git history for detail.
- **Session 3 (2026-10-26), Phase 2:** ADR 0002 (MQTTNIO 3 behind our own
  `MQTTTransport`), `HoundProtocol` and `@Observable HoundStore` out of the
  view controller, `MQTTNIOTransport` with reconnect (CocoaMQTT removed),
  `FakeMQTTTransport`, the unit-test target and shared scheme — see tag
  `m2` and git history for detail.
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
- **Session 5 (2026-10-27/28), Phase 6:** the user paid for the Apple
  Developer membership, so TestFlight was taken ahead of Phases 4–5. New
  bundle ID `io.henryerinjones.HellHounds`; `PrivacyInfo.xcprivacy`
  (UserDefaults, CA92.1), `ITSAppUsesNonExemptEncryption = NO`, a
  local-network usage string; icon PNGs without an alpha channel. First run
  on the user's iPhone 14 Pro on the fake transport (checked by screenshot
  and OCR). The user registered the explicit App ID and created the App
  Store Connect record; build 1.0 (1) archived and uploaded with
  `tools/testflight/ExportOptions.plist`; the user and one friend
  (internal testers) both installed it from TestFlight. **Phase 6 done.**
  Detail in the Phase 6 plan below.

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

Rename devices, pick an SF Symbol or photo, persisted with SwiftData and
synced through iCloud (CloudKit).

Plan (session 6; the user chose iCloud sync in this phase):

1. ~~`HoundProfile` SwiftData model~~ — done (session 6): broker key (`host:port`, or `fake` on
   the fake transport so test names never mix with real hounds), hound
   index, optional name, SF Symbol and photo (external storage, downscaled
   JPEG), `modifiedAt`. CloudKit rules: every property optional or
   defaulted, no `@Attribute(.unique)`; duplicates (two devices naming the
   same hound offline) resolve to the newest `modifiedAt`.
2. ~~Edit sheet~~ — done (session 6): tap a card's icon or name to open it (name, symbol grid, photo picker, reset); the
   card shows the name and the photo or symbol instead of "Hound n".
3. ~~iCloud~~ — done (session 6): CloudKit container `iCloud.io.henryerinjones.HellHounds`,
   push entitlement and the remote-notification background mode. Real
   runs use the CloudKit store; the fake transport and tests use a local
   store, so test data never syncs.
4. ~~Tests~~ — done (session 6): a profile written to an on-disk store survives reopening it;
   duplicate resolution; a UI test renames a fake hound and relaunches.
5. Device check (two devices or device + Simulator signed in to the same
   iCloud account), then the user deploys the CloudKit schema to
   production in CloudKit Console before the next TestFlight build.

Session 6 detail: `HoundProfile.swift` (model, `HoundLook`,
`ModelContext.saveLook`), `ProfileStore.swift` (CloudKit store
`.private("iCloud.io.henryerinjones.HellHounds")`, falling back to a local
store if it can't open; the fake transport uses
`Application Support/FakeProfiles/`, emptied by `-resetProfiles YES`),
`HoundEditSheet.swift` (name, `PhotosPicker`, 16-symbol grid, reset; photos
redrawn at ≤ 512 px JPEG, which also drops location metadata).
`HellHounds.entitlements` (CloudKit + `aps-environment`) and
`HellHounds/Info.plist` (only `UIBackgroundModes` = remote-notification,
merged with the generated plist; excluded from the synchronized group's
resources). A signed device build (`-allowProvisioningUpdates`) put the
container in the provisioning profile, so the App ID has iCloud and push.
Tests: 6 new unit tests (reopen an on-disk store with name + 200 KB photo,
update not duplicate, newest duplicate wins and saving drops the rest,
title fallback, fake broker key, downscale to 512×256) — 46 in all; UI
test `testRenamedHoundKeepsItsNameAfterRelaunch` (fails with an in-memory
store) — 3 UI tests. Checked by hand in the Simulator on the fake
transport: picked the flame symbol and a photo, named the hound, saved,
relaunched; the card kept the photo and name.
Step 5 so far (session 6): local Mosquitto reachable on the LAN
(`192.168.1.92:1883`, Docker publishes on all interfaces) with
`hound-sim -n 3`; the iPhone dev build and the Simulator both launched with
`-mqttHost 192.168.1.92` (same broker key on both). The Simulator first had
no iCloud account (`CKAccountStatusNoAccount`, the store still opens, it
just doesn't sync); after signing in, CloudKit setup took ~30 s (zone save).
A rename on the phone ("Hound Renamed", hound index 2) reached the
Simulator after a relaunch (the Simulator gets no pushes), checked in its
`Profiles.store` with sqlite3 and on screen. Then a symbol (hound 1,
`tortoise.fill`) and a photo (hound 0, 43,670 bytes — under SwiftData's
external-storage threshold, so stored inline) set on the phone also
arrived, and the cards showed them. Not yet seen: the reverse direction
(Simulator → phone) and live updates through push on the phone.

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
- TestFlight installs start on the public broker, so testers control the
  real hounds (the user's choice, session 5).
- A development build run from Xcode and the TestFlight build share the
  bundle ID, so installing one on a phone replaces the other.
- Hound names are keyed by broker (`host:port`) and index, so the same
  hound reached through another address (an IP instead of a host name)
  shows its default name.
- Simulator tool: typing into a text field right after tapping it can drop
  characters ("Cerberus" became "Cer"); XCUITest's `typeText` was fine.
- SwiftData + CloudKit: never add `@Attribute(.unique)` or a non-optional
  relationship to `HoundProfile`, or the CloudKit store fails to open (the
  app then silently falls back to a local store; see the log category
  `ProfileStore`).

## Next steps

1. **Finish Phase 4, step 5.** Phone → Simulator sync is checked (name,
   symbol, photo); optionally check Simulator → phone the same way (both
   on `-mqttHost <Mac's LAN IP>`, never the public broker; relaunch the
   Simulator to fetch). Then the user deploys the schema
   (record type `CD_HoundProfile`) from Development to Production in
   CloudKit Console (icloud.developer.apple.com) — TestFlight builds use
   Production and won't sync until then. Bump the build number and upload
   build 1.0 (2).
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
