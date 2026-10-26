#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["paho-mqtt>=2.1,<3"]
# ///
"""Smoke-test hound_sim.py by acting like the app.

Starts the simulator on a random topic prefix (so real hounds are never
touched), polls every hound, toggles and dims one, and checks the status
replies. Exits non-zero on failure.
"""

from __future__ import annotations

import argparse
import json
import queue
import secrets
import subprocess
import sys
import time
from pathlib import Path

import paho.mqtt.client as mqtt

HERE = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="broker.hivemq.com")
    parser.add_argument("--port", type=int, default=1883)
    parser.add_argument("-n", "--count", type=int, default=4)
    parser.add_argument("--escaped", action="store_true", help="run the sim with --escaped")
    args = parser.parse_args()

    prefix = f"HellHounds-SimCheck-{secrets.token_hex(4)}"
    sim_cmd = [
        sys.executable, str(HERE / "hound_sim.py"),
        "--host", args.host, "--port", str(args.port),
        "--prefix", prefix, "--count", str(args.count), "--poll-only",
    ]
    if args.escaped:
        sim_cmd.append("--escaped")

    statuses: queue.Queue[tuple[int, dict]] = queue.Queue()

    def on_message(client, userdata, message):
        index = int(message.topic.split("/")[1])
        # Same tolerance as the app: drop backslashes before parsing.
        text = message.payload.decode().replace("\\", "")
        statuses.put((index, json.loads(text)))

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"sim-check-{secrets.token_hex(4)}")
    client.on_message = on_message
    client.connect(args.host, args.port, keepalive=60)
    client.subscribe(f"{prefix}/+/status-json", qos=1)
    client.loop_start()

    sim = subprocess.Popen(sim_cmd)
    failures = 0

    def expect(label: str, index: int, check) -> None:
        nonlocal failures
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                got_index, status = statuses.get(timeout=deadline - time.monotonic())
            except queue.Empty:
                break
            if got_index == index and check(status):
                print(f"ok    {label}: {status}")
                return
        print(f"FAIL  {label}")
        failures += 1

    def poll(index: int) -> None:
        client.publish(f"{prefix}/{index}/msg", "0")

    try:
        time.sleep(3)  # let the sim connect and subscribe
        for i in range(args.count):
            poll(i)
            expect(f"hound {i} answers poll", i, lambda s: set(s) == {"ledState", "ledLvl", "battery"})

        client.publish(f"{prefix}/1/set-state", "1")
        time.sleep(0.5)
        poll(1)
        expect("set-state 1 turns hound 1 on", 1, lambda s: s["ledState"] == 1)

        client.publish(f"{prefix}/1/set-level", "42")
        time.sleep(0.5)
        poll(1)
        expect("set-level 42 dims hound 1", 1, lambda s: s["ledLvl"] == 42)

        client.publish(f"{prefix}/1/set-state", "0")
        time.sleep(0.5)
        poll(1)
        expect("set-state 0 turns hound 1 off", 1, lambda s: s["ledState"] == 0 and s["ledLvl"] == 42)
    finally:
        sim.terminate()
        sim.wait(timeout=10)
        client.loop_stop()
        client.disconnect()

    print("PASS" if failures == 0 else f"{failures} check(s) failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
