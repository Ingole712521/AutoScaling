"""Shared MQTT helpers for load tests, probes, and cluster proof scripts."""

from __future__ import annotations

import paho.mqtt.client as mqtt


def connack_ok(reason_code: object) -> bool:
    if reason_code is None:
        return False
    return getattr(reason_code, "value", reason_code) == 0


def apply_mqtt_credentials(
    client: mqtt.Client,
    username: str | None,
    password: str | None,
) -> None:
    if username:
        client.username_pw_set(username, password or "")
