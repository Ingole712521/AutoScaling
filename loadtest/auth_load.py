#!/usr/bin/env python3
"""Authenticated MQTT load clients with connect latency and failure metrics."""

from __future__ import annotations

import random
import statistics
import threading
import time
from dataclasses import dataclass, field

import paho.mqtt.client as mqtt

from mqtt_common import apply_mqtt_credentials, connack_ok


@dataclass
class AuthLoadMetrics:
    target_clients: int = 0
    connected: int = 0
    failures: int = 0
    disconnects: int = 0
    latencies_ms: list[float] = field(default_factory=list)

    @property
    def success_rate_pct(self) -> float:
        total = self.connected + self.failures
        if total == 0:
            return 0.0
        return 100.0 * self.connected / total

    def latency_summary(self) -> dict[str, float]:
        if not self.latencies_ms:
            return {}
        sorted_lat = sorted(self.latencies_ms)
        return {
            "min_ms": sorted_lat[0],
            "p50_ms": statistics.median(sorted_lat),
            "p95_ms": sorted_lat[int(0.95 * (len(sorted_lat) - 1))],
            "max_ms": sorted_lat[-1],
            "avg_ms": statistics.mean(sorted_lat),
        }

    def as_table_rows(self, auth_method: str = "Username / Password") -> list[tuple[str, str]]:
        lat = self.latency_summary()
        latency_val = (
            f"p50={lat['p50_ms']:.1f}ms p95={lat['p95_ms']:.1f}ms avg={lat['avg_ms']:.1f}ms"
            if lat
            else "n/a"
        )
        return [
            ("Authentication Method", auth_method),
            ("Concurrent Authenticated Clients", str(self.connected)),
            ("Authentication Failures", str(self.failures)),
            ("Success Rate", f"{self.success_rate_pct:.1f}%"),
            ("Authentication Latency", latency_val),
        ]


class AuthLoadClient(threading.Thread):
    def __init__(
        self,
        host: str,
        port: int,
        client_id: str,
        username: str,
        password: str,
        stop_event: threading.Event,
        metrics: AuthLoadMetrics,
        metrics_lock: threading.Lock,
        connect_timeout_sec: float,
        conn_only: bool = True,
    ) -> None:
        super().__init__(daemon=True)
        self.host = host
        self.port = port
        self.client_id = client_id
        self.username = username
        self.password = password
        self.stop_event = stop_event
        self.metrics = metrics
        self.metrics_lock = metrics_lock
        self.connect_timeout_sec = connect_timeout_sec
        self.conn_only = conn_only
        self._live = False

    def is_live(self) -> bool:
        return self._live

    def run(self) -> None:
        ready = threading.Event()
        conn_rc: list[object] = [None]
        t0 = time.perf_counter()

        def on_connect(_c, _u, _f, reason_code, _p) -> None:
            conn_rc[0] = reason_code
            ready.set()

        def on_disconnect(_c, _u, _flags, _reason_code, _p) -> None:
            self._live = False
            if not self.stop_event.is_set():
                with self.metrics_lock:
                    self.metrics.disconnects += 1

        client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=self.client_id,
            protocol=mqtt.MQTTv311,
        )
        apply_mqtt_credentials(client, self.username, self.password)
        client.on_connect = on_connect
        client.on_disconnect = on_disconnect

        try:
            client.connect(self.host, self.port, keepalive=60)
            client.loop_start()
            if not ready.wait(timeout=self.connect_timeout_sec):
                with self.metrics_lock:
                    self.metrics.failures += 1
                return
            latency_ms = (time.perf_counter() - t0) * 1000.0
            if not connack_ok(conn_rc[0]):
                with self.metrics_lock:
                    self.metrics.failures += 1
                return
            self._live = True
            with self.metrics_lock:
                self.metrics.connected += 1
                self.metrics.latencies_ms.append(latency_ms)

            if self.conn_only:
                while not self.stop_event.is_set() and self._live:
                    self.stop_event.wait(timeout=30.0)
                return

            while not self.stop_event.is_set() and self._live:
                client.publish("loadtest/auth-scale", "{}", qos=0)
                self.stop_event.wait(timeout=0.05)
        except Exception:
            with self.metrics_lock:
                self.metrics.failures += 1
        finally:
            try:
                client.loop_stop()
                client.disconnect()
            except Exception:
                pass


def run_auth_load(
    host: str,
    port: int,
    username: str,
    password: str,
    client_count: int,
    *,
    connect_stagger_sec: float = 0.05,
    connect_timeout_sec: float = 60.0,
    hold_sec: float = 30.0,
) -> AuthLoadMetrics:
    metrics = AuthLoadMetrics(target_clients=client_count)
    stop = threading.Event()
    lock = threading.Lock()
    threads: list[AuthLoadClient] = []

    for i in range(client_count):
        t = AuthLoadClient(
            host,
            port,
            client_id=f"auth-{i}-{int(time.time())}",
            username=username,
            password=password,
            stop_event=stop,
            metrics=metrics,
            metrics_lock=lock,
            connect_timeout_sec=connect_timeout_sec,
            conn_only=True,
        )
        threads.append(t)
        t.start()
        time.sleep(connect_stagger_sec)

    deadline = time.time() + connect_timeout_sec + client_count * connect_stagger_sec + 10
    while time.time() < deadline:
        with lock:
            done = metrics.connected + metrics.failures
        if done >= client_count:
            break
        time.sleep(0.5)

    time.sleep(hold_sec)
    stop.set()
    for t in threads:
        t.join(timeout=5.0)
    return metrics


class SustainedAuthPool:
    """Authenticated MQTT clients held open; supports incremental connects and publish load."""

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        *,
        connect_timeout_sec: float = 60.0,
        topic: str = "loadtest/auth-scale",
    ) -> None:
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.connect_timeout_sec = connect_timeout_sec
        self.topic = topic
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._metrics = AuthLoadMetrics()
        self._threads: list[AuthLoadClient] = []

    def start(
        self,
        count: int,
        *,
        stagger_sec: float = 0.05,
        conn_only: bool = True,
        publish_interval_sec: float = 0.05,
    ) -> None:
        self._metrics.target_clients += count
        for i in range(count):
            client = AuthLoadClient(
                self.host,
                self.port,
                client_id=f"auth-pool-{len(self._threads)}-{int(time.time())}",
                username=self.username,
                password=self.password,
                stop_event=self._stop,
                metrics=self._metrics,
                metrics_lock=self._lock,
                connect_timeout_sec=self.connect_timeout_sec,
                conn_only=conn_only,
            )
            self._threads.append(client)
            client.start()
            time.sleep(stagger_sec)

    def wait_connected(self, min_count: int, timeout_sec: float) -> bool:
        deadline = time.time() + timeout_sec
        while time.time() < deadline:
            if self.live_count() >= min_count:
                return True
            time.sleep(1.0)
        return self.live_count() >= min_count

    def live_count(self) -> int:
        return sum(1 for t in self._threads if t.is_live())

    def snapshot(self) -> AuthLoadMetrics:
        with self._lock:
            snap = AuthLoadMetrics(
                target_clients=self._metrics.target_clients,
                connected=self._metrics.connected,
                failures=self._metrics.failures,
                disconnects=self._metrics.disconnects,
                latencies_ms=list(self._metrics.latencies_ms),
            )
        snap.connected = self.live_count()
        return snap

    def stop(self, join_timeout_sec: float = 10.0) -> AuthLoadMetrics:
        self._stop.set()
        for t in self._threads:
            t.join(timeout=join_timeout_sec)
        return self.snapshot()


def try_connect(
    host: str,
    port: int,
    *,
    username: str | None = None,
    password: str | None = None,
    timeout_sec: float = 15.0,
) -> tuple[bool, object | None, float | None]:
    """Single connect attempt; returns (ok, connack_rc, latency_ms)."""
    ready = threading.Event()
    conn_rc: list[object] = [None]
    t0 = time.perf_counter()

    def on_connect(_c, _u, _f, reason_code, _p) -> None:
        conn_rc[0] = reason_code
        ready.set()

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"auth-probe-{int(time.time())}-{random.randint(0, 9999)}",
        protocol=mqtt.MQTTv311,
    )
    apply_mqtt_credentials(client, username, password)
    client.on_connect = on_connect
    try:
        client.connect(host, port, keepalive=30)
        client.loop_start()
        if not ready.wait(timeout=timeout_sec):
            return False, None, None
        latency_ms = (time.perf_counter() - t0) * 1000.0
        return connack_ok(conn_rc[0]), conn_rc[0], latency_ms
    except Exception:
        return False, None, None
    finally:
        try:
            client.loop_stop()
            client.disconnect()
        except Exception:
            pass
