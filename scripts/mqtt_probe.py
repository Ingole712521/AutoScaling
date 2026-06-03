#!/usr/bin/env python3
"""Single-client MQTT probe against the NLB."""

from __future__ import annotations

import argparse
import os
import sys
import time

import paho.mqtt.client as mqtt


def connack_ok(reason_code: object) -> bool:
    if reason_code is None:
        return False
    return getattr(reason_code, "value", reason_code) == 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.environ.get("MQTT_HOST", ""))
    parser.add_argument("--port", type=int, default=int(os.environ.get("MQTT_PORT", "1883")))
    parser.add_argument("--topic", default=os.environ.get("MQTT_TOPIC", "loadtest/probe"))
    args = parser.parse_args()

    if not args.host:
        print("Error: --host or MQTT_HOST required", file=sys.stderr)
        return 1

    state = {"rc": None}
    done = False

    def on_connect(_c, _u, _f, reason_code, _p):
        state["rc"] = reason_code
        nonlocal done
        done = True

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"probe-{int(time.time())}",
        protocol=mqtt.MQTTv311,
    )
    client.on_connect = on_connect

    print(f"Connecting to {args.host}:{args.port} ...")
    try:
        client.connect(args.host, args.port, keepalive=30)
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1

    client.loop_start()
    deadline = time.time() + 15
    while time.time() < deadline and not done:
        time.sleep(0.05)

    if not connack_ok(state["rc"]):
        print(f"FAIL: CONNACK={state['rc']}")
        client.loop_stop()
        return 1

    result = client.publish(args.topic, '{"ok":true}', qos=0)
    time.sleep(0.5)
    client.loop_stop()
    client.disconnect()

    if result.rc != mqtt.MQTT_ERR_SUCCESS:
        print(f"FAIL: publish rc={result.rc}")
        return 1

    print("OK: connected and published")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
