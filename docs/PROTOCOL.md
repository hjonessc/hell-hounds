# Hell Hounds MQTT protocol

How the app and the hounds talk. Written from the 2019 app; the code now lives in
`HellHounds/HoundProtocol.swift` and `HellHounds/HoundStore.swift`. The firmware isn't
available yet (Q1), so everything here comes from the app side; anything
about device behaviour that the app doesn't show is marked **unverified**.

The app, `tools/hound-sim/` and any future Android app must follow this
document. Change it whenever the protocol code changes.

## Broker and connection

| Setting | Value |
|---|---|
| Broker | `broker.hivemq.com` |
| Port | `1883` (plain TCP, no TLS) |
| Auth | none (empty username and password) |
| Client ID | `HellHounds-Test-<pid>` (any unique ID works) |
| Keep-alive | 60 s |
| Clean session | yes (CocoaMQTT default) |
| Last will | topic `/will`, payload `dieout` (not read by anything we know of) |

The broker is public, so anyone who knows the prefix can read and control
the hounds (see ADR 0001).

## Topics

Every device topic has the form

```
<prefix>/<index>/<leaf>
```

- `<prefix>` is `HellHounds-MQTT`.
- `<index>` is the device number as a decimal integer. The app uses
  `0`–`3`: cards 1, 2, 3 and "Jack" are indices 0, 1, 2 and 3.
- `<leaf>` is one of the leaves below.

| Leaf | Direction | QoS | Payload |
|---|---|---|---|
| `set-state` | app → hound | 0 | `"1"` = LED on, `"0"` = LED off |
| `set-level` | app → hound | 0 | brightness, integer `0`–`100` as a decimal string |
| `msg` | app → hound | 0 | status request; payload ignored (app sends `"0"`) |
| `status-json` | hound → app | app subscribes at 1 | status JSON, see below |

The app never sets the retain flag.

### `set-state`: on/off

**Watch out:** the constant names in the old code are the wrong way round
(`kMqttLedOn = "0"`, `kMqttLedOff = "1"`), but the code also swaps them back
when sending (`value ? kMqttLedOff : kMqttLedOn`). What actually goes over the
wire is **`"1"` when the switch is on, `"0"` when it's off**. That matches
the status JSON, where `ledState == 1` means on.

> ADR 0001 and the first version of STATE.md said "LED on is sent as `"0"`".
> That came from the constant names and is wrong for the wire.

### `set-level`: brightness

An integer from 0 to 100, rounded from the slider and sent as a string such as
`"42"`. The slider isn't continuous, so one message goes out when it's
released, not while it's dragged. Setting the level doesn't turn the LED on
or off (**unverified** what the firmware does with level `0`).

### `msg`: status poll

Publishing anything to `<prefix>/<index>/msg` asks hound `<index>` to send
its `status-json`. The app polls indices 0–3 **once**, 0.2 s after the
connection is accepted. It doesn't poll again after that.

### `status-json`: device status

```json
{"ledState": 1, "ledLvl": 42, "battery": 87}
```

| Key | Type | Meaning |
|---|---|---|
| `ledState` | bool or int | `true` / `1` = on, anything else = off (the real firmware sends a bool) |
| `ledLvl` | int | brightness 0–100 |
| `battery` | int | battery charge in percent, 0–100 (the app warns below 20) |

How the app parses it:

- It **removes every backslash** from the payload before parsing. This
  suggests the firmware sends escaped JSON such as
  `{\"ledState\":1,\"ledLvl\":42,\"battery\":87}`. A plain JSON payload
  works too. Senders (including the simulator) should send plain JSON, and
  receivers should accept both.
- `ledLvl` and `battery` must be integers; `ledState` may be a boolean or an
  integer. Any other type makes the parse fail and the message is dropped.
- A missing `ledState` is read as off. A missing `ledLvl` or `battery`
  leaves that value as it was (the 2019 app crashed here, as it did on an
  index above 3).
- The index comes from the second part of the topic. A message whose index
  isn't an integer, or isn't a hound the app knows, is dropped.

The app subscribes to `<prefix>/<index>/status-json` for indices 0–3, one
topic each (no wildcard yet; ADR 0001 plans `<prefix>/+/status-json`).

**Unverified (Q2):** whether a hound sends `status-json` on its own (after
a `set-state` / `set-level`, on a timer, or at boot), or only when polled
through `msg`. The old app gets later status only if the device sends it
unprompted: it doesn't update its model from its own commands, and it polls
only once.

## Seen from a real hound (2026-10-26)

A real hound with index 1 was on the public broker during testing. When it
got `set-state 1`, it published, unprompted and within a second:

| Topic | Payload |
|---|---|
| `HellHounds-MQTT/1/status-json` | `{"ledState":true,"ledLvl":81,"battery":90}`: **plain JSON with a boolean `ledState`**, not escaped and not `1`/`0` |
| `HellHounds-MQTT/1/status` | `LED is: 1\nLVL is: 81\n` (text) |
| `HellHounds-MQTT/1/BatStats` | ` SOC: 90 %\n4.00 V \| -79 mA\nTime: 155.45` (text: charge, voltage, current, and probably uptime in hours) |

So the firmware sends status by itself after a command (at least after
`set-state`), which partly answers Q2. Receivers must accept `ledState` as a
boolean or as `1`/`0`; the app does now. `status` and `BatStats` aren't used
yet. `BatStats` has voltage and current that the app could show later.

## Lifecycle

1. Connect. When the connection is accepted, subscribe to
   `status-json` for each index.
2. After 0.2 s, publish to `msg` for each index.
3. Any `status-json` received marks that hound as connected and updates its
   state.
4. User actions publish `set-state` / `set-level` to that hound's index.
5. On disconnect, mark every hound as not connected.

Nothing tells the app a hound has gone offline: no LWT per device, no retained
status and no timeout. A hound stays "connected" until the app's own MQTT
connection drops.

## Master control

There's no broadcast topic. The master switch and slider send the same
`set-state` / `set-level` message to each index in turn. The master card
shows a summary of the connected hounds: **on** if any is on,
**brightness** = the highest, **battery** = the lowest.

## Not used

Defined in the old code but never sent or subscribed to:

- leaf `status` (`kTopicStatus`)
- `HellHounds-MQTT$<leaf>`, an "all hounds" topic (`fullTopicForAllHounds`,
  no slash, never called)
- client certificate `client-keycert.p12` (deleted, along with its unused loader; Q6)
