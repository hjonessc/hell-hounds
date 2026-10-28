# Project state

_Last updated: 2026-10-28 (session 6)_

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
**Phase 4 — Names and images: done (session 6).** Sync checked in
Production: the user installed 1.0 (2) from TestFlight on two phones and a
name and photo synced.
**Phase 5 — README: not started (skipped for now).**
**Phase 6 — TestFlight: done (session 5).** Taken ahead of Phases 4–5 once
the user paid for the Apple Developer membership (Q4).

## Done

- **Sessions 1–2 (2026-10-25), kickoff + Phase 1:** requirements and ADR 0001;
  PROTOCOL.md (on the wire `"1"` = on, `"0"` = off, correcting ADR 0001),
  `tools/hound-sim/`, the top-level Xcode project, leftovers deleted, clean
  clone checked against the sim — see tag `m1` and git history for detail.
- **Session 3 (2026-10-26), Phase 2:** ADR 0002 (MQTTNIO 3 behind our own
  `MQTTTransport`), `HoundStore`, fake transport, unit tests — see tag `m2`.
- **Session 4 (2026-10-26/27), Phase 3:** SwiftUI app, discovery (probe
  0..<8 plus `+/status-json`), cards with `BatteryIndicator`, connection
  banner, Settings tab with broker switching (`AppModel`), Liquid Glass tab
  bar, UI test target, check against `hound-sim -n 5` — see tag `m3` and
  git history for detail.
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
- **Session 6 (2026-10-27/28), Phase 4:** the user chose iCloud sync in
  this phase. `HoundProfile` (SwiftData, CloudKit-compatible, keyed by
  broker + index), edit sheet from each card (name, 16 symbols, photo
  downscaled to 512 px), CloudKit + push entitlements, `HellHounds/Info.plist`
  for the remote-notification background mode. 46 unit + 3 UI tests.
  Sync checked phone ↔ Simulator on local Mosquitto over the LAN, then the
  user deployed the schema to Production, build 1.0 (2) was uploaded, and
  the user saw a name and photo sync between two TestFlight installs.
  **Phase 4 done.** Detail in the Phase 4 plan below.

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
5. ~~Device check and schema deploy~~ — done (session 6): phone →
   Simulator sync checked (below), and the user checked Simulator → phone and two TestFlight
   installs of 1.0 (2) (name and photo synced); the user deployed the schema
   (`CD_HoundProfile`) to Production in CloudKit Console; build 1.0 (2)
   uploaded with the usual archive/export commands.

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

1. **Photo crop (user request, session 6; the user deferred it, so ask
   before starting).** Today `HoundEditSheet` keeps the whole photo and
   the card fills its circle from the centre. Proposed (about an hour):
   after picking, a crop screen with the photo behind a circle outline,
   pinch to zoom and drag to move (clamped so the circle stays filled),
   Cancel / Choose; crop on Choose to the square inside the circle at
   512 px, so `photoData` and the CloudKit schema don't change. Unit test
   the crop maths (zoom + offset → source rect). Trade-off told to the
   user: re-cropping means re-picking the photo; keeping the original plus
   zoom/offset would allow re-editing but syncs larger photos and needs a
   schema change and deploy.
2. Then pick the next phase: 5 (README with screenshots from UI tests) is
   unblocked; 7 waits on Q1/Q3, 8 on Q5.
3. Move MQTTNIO from `3.0.0-rc.1` to `3.0.0` once it's tagged (separate commit).

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
configurations first; builds 1 and 2 are used; after any change to
`HoundProfile`, deploy the schema to Production in CloudKit Console first):

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
