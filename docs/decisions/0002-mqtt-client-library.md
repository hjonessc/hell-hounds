# 0002 — MQTT client library

- **Status**: proposed
- **Date**: 2026-10-26

## Context

The app uses CocoaMQTT 2.1.6 (pinned exactly) through a delegate on the
513-line `ViewController`. Phase 2 pulls an MQTT transport protocol and an
`@Observable` device model out of that controller, and Phase 3 rewrites the
UI in SwiftUI, so this is the cheapest time to change libraries. The app needs
only a small part of MQTT 3.1.1: connect over plain TCP to
`broker.hivemq.com:1883`, a wildcard subscribe to `status-json`, QoS 0
publishes of short strings, keepalive, and reconnecting after the app has been
in the background. ADR 0001 sets iOS 26 and asks for code ready for Swift 6.

Options as of 2026-10-26:

| | CocoaMQTT 2.4.1 | CocoaMQTT 3 | MQTTNIO 3.0.0-rc.1 | MQTTNIO 2.13.0 | Write our own on Network.framework |
|---|---|---|---|---|---|
| State | LTS line, released 2026-09-08 | `master` only, not released, no date | release candidate, 2026-09-28; repo active | stable, 2026-02-05 | — |
| API | delegate / closures, GCD | delegate (Starscream removed) | async/await, structured (`withConnection`, `subscribe { for try await … }`) | async/await plus futures | whatever we write |
| Concurrency | "usable from Swift 6" check in CI; the library itself is Swift 5 | same | written in Swift 6 mode, `NonisolatedNonsendingByDefault` | Swift 5.x, Sendable annotations | ours |
| Transport | MqttCocoaAsyncSocket (Objective-C GCD socket) + Starscream | MqttCocoaAsyncSocket | SwiftNIO on Network.framework (NIOTransportServices) | same | Network.framework |
| Dependencies | 2 | 1 | 8 Apple packages (swift-nio, -ssl, -transport-services, -extras, -log, -configuration, -http-types, -distributed-tracing) | several Apple NIO packages (not counted) | 0 |
| Auto-reconnect | built in | built in | none, the caller loops | none | ours |
| Minimum OS | iOS 12 | iOS 12 | iOS 18 | iOS 13 | — |
| License | MIT-style (NOASSERTION on GitHub) | same | Apache-2.0 | Apache-2.0 | — |

The 2.x LTS line takes only fixes. It will be kept for at least 12 months
after 3.0 ships, and its transport (CocoaAsyncSocket) is frozen.

## Decision

- **Switch to MQTTNIO 3** (`swift-server-community/mqtt-nio`). Pin
  `3.0.0-rc.1` exactly now and move to `3.0.0` when it is tagged, as a
  separate commit.
- Hide it behind our own `MQTTTransport` protocol (connect, subscribe as an
  `AsyncSequence` of messages, publish, connection state). The model and UI see
  only that protocol and our own message type. Nothing from NIO (no
  `ByteBuffer`) leaks out of the adapter file.
- The adapter owns reconnecting: a loop with backoff around `withConnection`,
  started and stopped by the app's scene phase. A clean session with the same
  subscriptions on every connect is enough, since the protocol has no retained
  state to resume (the `MQTTSession` type in 3.0 isn't needed yet).
- Leave out the trait we don't use. If the package allows it, depend on
  MQTTNIO with `traits: []` to drop distributed tracing.
- **Fallback:** if the RC blocks Phase 2 (build problems on Xcode / iOS 26, or
  a bug we can't work around), use CocoaMQTT 2.4.1 behind the same protocol.
  Its adapter turns the delegate into an `AsyncStream`. Because of the
  protocol, only the adapter changes.
- Rejected: **writing our own client** (tempting with so small a slice of the
  protocol, but keepalive, packet framing and partial reads become ours to
  test and maintain); **CocoaMQTT 3** (not released); **MQTTNIO 2.x** (its
  API is the one 3.0 replaces).

## Consequences

- The transport code is async/await and checked in Swift 6 mode, which fits
  `@Observable` models and SwiftUI `.task` lifetimes. The app target can
  turn on Swift 6 language mode once `ViewController` is gone (Phase 3).
- We depend on a release candidate until 3.0.0 is tagged. The API may still
  change slightly before then. Only the adapter is affected.
- The package graph grows from 3 to about 10 packages, and the binary probably gets
  a few MB bigger because of SwiftNIO (not measured). That's fine for a hobby app; measure it
  again before TestFlight (Phase 6).
- Reconnect logic is ours to write and test. The fake transport and
  `hound-sim` cover it.
- MQTTNIO's iOS 18 minimum is under our iOS 26 minimum, so no problem there.
- MQTTNIO also supports Android, which might matter for Phase 8 (Q5) if a
  Swift-on-Android route is ever looked at.
- Starscream and CocoaAsyncSocket leave the dependency graph, along with
  the delegate code in `ViewController` and the unused `.p12` loader.
