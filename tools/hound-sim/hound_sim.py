#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["paho-mqtt>=2.1,<3"]
# ///
"""Simulate N Hell Hounds on an MQTT broker.

Implements the device side of docs/PROTOCOL.md: answers `msg` polls with
`status-json`, obeys `set-state` and `set-level`, and prints every state
change. Run `uv run hound_sim.py --help` for options.
"""

from __future__ import annotations

import argparse
import json
import secrets
import signal
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime

import paho.mqtt.client as mqtt

DEFAULT_HOST = "broker.hivemq.com"
DEFAULT_PORT = 1883
DEFAULT_PREFIX = "HellHounds-MQTT"

LED_ON = "1"
LED_OFF = "0"


@dataclass
class Hound:
    index: int
    on: bool = False
    level: int = 50
    battery: float = 100.0

    def status(self) -> dict[str, int]:
        return {
            "ledState": 1 if self.on else 0,
            "ledLvl": self.level,
            "battery": round(self.battery),
        }

    def describe(self) -> str:
        led = "on " if self.on else "off"
        return f"LED {led}  level {self.level:3d}  battery {round(self.battery):3d}%"


def log(message: str) -> None:
    stamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{stamp}] {message}", flush=True)


class Simulator:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.prefix = args.prefix
        self.lock = threading.Lock()
        self.hounds = {
            i: Hound(index=i, battery=initial_battery(n, args.count))
            for n, i in enumerate(range(args.start_index, args.start_index + args.count))
        }
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=args.client_id or f"hound-sim-{secrets.token_hex(4)}",
        )
        self.client.on_connect = self.on_connect
        self.client.on_disconnect = self.on_disconnect
        self.client.on_message = self.on_message

    def topic(self, index: int, leaf: str) -> str:
        return f"{self.prefix}/{index}/{leaf}"

    # MARK: MQTT callbacks

    def on_connect(self, client, userdata, flags, reason_code, properties) -> None:
        if reason_code.is_failure:
            log(f"connect failed: {reason_code}")
            return
        log(f"connected to {self.args.host}:{self.args.port}, prefix {self.prefix!r}")
        for index in self.hounds:
            for leaf in ("set-state", "set-level", "msg"):
                client.subscribe(self.topic(index, leaf), qos=0)
        with self.lock:
            for hound in self.hounds.values():
                log(f"hound {hound.index}: {hound.describe()}")
                if not self.args.poll_only:
                    self.publish_status(hound)

    def on_disconnect(self, client, userdata, flags, reason_code, properties) -> None:
        log(f"disconnected: {reason_code}")

    def on_message(self, client, userdata, message: mqtt.MQTTMessage) -> None:
        parts = message.topic.split("/")
        if len(parts) != 3 or parts[0] != self.prefix:
            return
        try:
            index = int(parts[1])
        except ValueError:
            return
        hound = self.hounds.get(index)
        if hound is None:
            return
        payload = message.payload.decode("utf-8", errors="replace").strip()
        leaf = parts[2]
        with self.lock:
            if leaf == "msg":
                log(f"hound {index}: polled")
                self.publish_status(hound)
            elif leaf == "set-state":
                self.set_state(hound, payload)
            elif leaf == "set-level":
                self.set_level(hound, payload)

    # MARK: Commands

    def set_state(self, hound: Hound, payload: str) -> None:
        if payload not in (LED_ON, LED_OFF):
            log(f"hound {hound.index}: ignored set-state {payload!r}")
            return
        hound.on = payload == LED_ON
        log(f"hound {hound.index}: {hound.describe()}  <- set-state {payload}")
        self.push_status(hound)

    def set_level(self, hound: Hound, payload: str) -> None:
        try:
            level = int(payload)
        except ValueError:
            log(f"hound {hound.index}: ignored set-level {payload!r}")
            return
        hound.level = max(0, min(100, level))
        log(f"hound {hound.index}: {hound.describe()}  <- set-level {payload}")
        self.push_status(hound)

    # MARK: Status

    def push_status(self, hound: Hound) -> None:
        """Send status unprompted, unless simulating poll-only firmware."""
        if not self.args.poll_only:
            self.publish_status(hound)

    def publish_status(self, hound: Hound) -> None:
        payload = json.dumps(hound.status(), separators=(",", ":"))
        if self.args.escaped:
            payload = payload.replace('"', '\\"')
        self.client.publish(self.topic(hound.index, "status-json"), payload, qos=0)

    def drain(self, minutes: float) -> None:
        """Lower each lit hound's battery; push status when the percent changes."""
        with self.lock:
            for hound in self.hounds.values():
                if not hound.on:
                    continue
                before = round(hound.battery)
                hound.battery = max(0.0, hound.battery - self.args.drain * minutes)
                if round(hound.battery) != before:
                    log(f"hound {hound.index}: {hound.describe()}  (drain)")
                    self.push_status(hound)

    # MARK: Run

    def run(self) -> None:
        stop = threading.Event()
        signal.signal(signal.SIGINT, lambda *_: stop.set())
        signal.signal(signal.SIGTERM, lambda *_: stop.set())

        self.client.connect_async(self.args.host, self.args.port, keepalive=60)
        self.client.loop_start()
        tick = 5.0
        while not stop.wait(tick):
            if self.args.drain > 0:
                self.drain(tick / 60)
        log("stopping")
        self.client.disconnect()
        self.client.loop_stop()


def initial_battery(n: int, count: int) -> float:
    """Spread batteries from 100% down to 10% so low-battery UI shows up."""
    if count <= 1:
        return 100.0
    return 100.0 - 90.0 * n / (count - 1)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"broker host (default {DEFAULT_HOST})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"broker port (default {DEFAULT_PORT})")
    parser.add_argument("--prefix", default=DEFAULT_PREFIX, help=f"topic prefix (default {DEFAULT_PREFIX})")
    parser.add_argument("-n", "--count", type=int, default=4, help="number of hounds (default 4)")
    parser.add_argument("--start-index", type=int, default=0, help="index of the first hound (default 0)")
    parser.add_argument("--client-id", help="MQTT client ID (default: random)")
    parser.add_argument(
        "--poll-only",
        action="store_true",
        help="send status only when polled via msg, never unprompted (PROTOCOL.md Q2)",
    )
    parser.add_argument(
        "--escaped",
        action="store_true",
        help='send status JSON with escaped quotes ({\\"ledState\\":1,...}), as the firmware may',
    )
    parser.add_argument(
        "--drain",
        type=float,
        default=0.0,
        metavar="PCT",
        help="battery percent lost per minute while a hound's LED is on (default 0)",
    )
    args = parser.parse_args(argv)
    if args.count < 1:
        parser.error("--count must be at least 1")
    return args


def main(argv: list[str]) -> None:
    Simulator(parse_args(argv)).run()


if __name__ == "__main__":
    main(sys.argv[1:])
