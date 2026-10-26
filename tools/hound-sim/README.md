# hound-sim

Fake Hell Hounds on a real MQTT broker. This is the device side of
[docs/PROTOCOL.md](../../docs/PROTOCOL.md): use it to try the app while the
real hounds are off.

Needs [uv](https://docs.astral.sh/uv/). The script declares its own
dependency (`paho-mqtt`), so there's nothing to install.

```bash
uv run tools/hound-sim/hound_sim.py
```

By default this runs 4 hounds (indices 0–3) on `broker.hivemq.com` with
prefix `HellHounds-MQTT`, the same as the app. **If the real hounds are on,
they get the same commands.** Pass `--prefix` to keep them apart.

| Option | Effect |
|---|---|
| `--host`, `--port`, `--prefix` | Broker and topic prefix |
| `-n`, `--count` / `--start-index` | How many hounds, and the first index |
| `--poll-only` | Send status only when polled via `msg` (one answer to PROTOCOL.md Q2) |
| `--escaped` | Send status as `{\"ledState\":1,...}`, as the firmware may |
| `--drain PCT` | Lit hounds lose `PCT` % battery per minute |

The hounds start off at level 50, with batteries spread from 100% down to 10%
so the low-battery state shows up. Without `--poll-only`, each hound sends its
status when it connects and after every change, so the old app (which polls
only once) still shows updates.

## Smoke test

```bash
uv run tools/hound-sim/check_sim.py
```

Starts the simulator on a random prefix, acts like the app (poll, toggle, dim)
and checks the replies. Prints `PASS` and exits 0 on success. Add `--escaped`
to test the escaped JSON format.
