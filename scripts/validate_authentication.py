#!/usr/bin/env python3
"""
MQTT authentication validation for EMQX on AWS:
  - Username/password authentication enabled
  - Built-in database backend configured
  - Successful authentication under load (default 2,000 clients)
  - Metrics: concurrent clients, failures, success rate, latency
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "loadtest"))

from auth_load import AuthLoadMetrics, run_auth_load, try_connect  # noqa: E402


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str
    skipped: bool = False


@dataclass
class AuthReport:
    results: list[CheckResult] = field(default_factory=list)

    def add(self, name: str, passed: bool, detail: str, *, skipped: bool = False) -> None:
        self.results.append(CheckResult(name, passed, detail, skipped))
        tag = "SKIP" if skipped else ("PASS" if passed else "FAIL")
        print(f"[{tag}] {name}")
        for line in detail.splitlines():
            print(f"      {line}")

    def ok(self) -> bool:
        return all(r.passed or r.skipped for r in self.results)


def emqx_login(core_ip: str, user: str, password: str) -> str | None:
    url = f"http://{core_ip}:18083/api/v5/login"
    try:
        r = requests.post(url, json={"username": user, "password": password}, timeout=15)
        if r.status_code != 200:
            return None
        return r.json().get("token")
    except requests.RequestException:
        return None


def check_auth_backend(
    report: AuthReport,
    core_ip: str,
    dashboard_user: str,
    dashboard_password: str,
) -> bool:
    token = emqx_login(core_ip, dashboard_user, dashboard_password)
    if not token:
        report.add("Authentication backend configured", False, "Dashboard login failed")
        return False

    url = f"http://{core_ip}:18083/api/v5/authentication"
    try:
        r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=15)
        r.raise_for_status()
        chains = r.json()
    except requests.RequestException as exc:
        report.add("Authentication backend configured", False, str(exc))
        return False

    if not isinstance(chains, list):
        chains = chains.get("data", []) if isinstance(chains, dict) else []

    builtin = [
        c for c in chains
        if c.get("mechanism") == "password_based" and c.get("backend") == "built_in_database"
    ]
    lines = []
    for c in builtin:
        lines.append(
            f"id={c.get('id')} enable={c.get('enable')} mechanism={c.get('mechanism')} "
            f"backend={c.get('backend')}"
        )
    if not lines:
        lines.append("No password_based + built_in_database authenticator found")

    enabled = any(c.get("enable") for c in builtin)
    report.add(
        "Authentication backend configured",
        bool(builtin) and enabled,
        "\n".join(lines),
    )
    return bool(builtin) and enabled


def check_auth_enabled_on_listener(
    report: AuthReport,
    core_ip: str,
    dashboard_user: str,
    dashboard_password: str,
) -> bool:
    token = emqx_login(core_ip, dashboard_user, dashboard_password)
    if not token:
        report.add("Username/password authentication enabled", False, "Dashboard login failed")
        return False

    url = f"http://{core_ip}:18083/api/v5/listeners"
    try:
        r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=15)
        r.raise_for_status()
        listeners = r.json()
    except requests.RequestException as exc:
        report.add("Username/password authentication enabled", False, str(exc))
        return False

    if isinstance(listeners, dict):
        listeners = listeners.get("data", listeners.get("listeners", []))

    tcp_default = None
    for item in listeners:
        if item.get("type") == "tcp" and item.get("name") in ("default", "tcp:default"):
            tcp_default = item
            break
        bind = str(item.get("bind", ""))
        if item.get("type") == "tcp" and ":1883" in bind:
            tcp_default = item
            break

    if not tcp_default:
        report.add(
            "Username/password authentication enabled",
            False,
            "TCP listener on 1883 not found in API",
        )
        return False

    authn = tcp_default.get("enable_authn", tcp_default.get("enable_auth", False))
    detail = f"listener={tcp_default.get('id', tcp_default.get('name'))} enable_authn={authn}"
    report.add("Username/password authentication enabled", bool(authn), detail)
    return bool(authn)


def check_anonymous_rejected(
    report: AuthReport,
    mqtt_host: str,
    mqtt_port: int,
) -> bool:
    ok, rc, _ = try_connect(mqtt_host, mqtt_port, username=None, password=None)
    passed = not ok
    detail = (
        "Anonymous connect rejected as expected"
        if passed
        else f"Anonymous connect succeeded (CONNACK={rc}) — auth may be disabled"
    )
    report.add("Anonymous connection rejected", passed, detail)
    return passed


def check_invalid_credentials(
    report: AuthReport,
    mqtt_host: str,
    mqtt_port: int,
    valid_user: str,
) -> bool:
    ok, rc, _ = try_connect(
        mqtt_host,
        mqtt_port,
        username=valid_user,
        password="wrong-password-intentionally",
    )
    passed = not ok
    detail = (
        "Invalid password rejected as expected"
        if passed
        else f"Invalid password accepted (CONNACK={rc})"
    )
    report.add("Invalid credentials rejected", passed, detail)
    return passed


def check_valid_credentials(
    report: AuthReport,
    mqtt_host: str,
    mqtt_port: int,
    username: str,
    password: str,
) -> bool:
    ok, rc, latency = try_connect(
        mqtt_host,
        mqtt_port,
        username=username,
        password=password,
    )
    detail = (
        f"CONNACK OK, latency={latency:.1f}ms"
        if ok and latency is not None
        else f"Connect failed (CONNACK={rc})"
    )
    report.add("Valid credentials accepted", ok, detail)
    return ok


def print_metrics_table(metrics: AuthLoadMetrics) -> None:
    print("")
    print("=" * 60)
    print("AUTHENTICATION LOAD TEST METRICS")
    print("=" * 60)
    print(f"{'Metric':<36} {'Value':>20}")
    print("-" * 60)
    for label, value in metrics.as_table_rows():
        print(f"{label:<36} {value:>20}")
    print("=" * 60)


def check_auth_under_load(
    report: AuthReport,
    mqtt_host: str,
    mqtt_port: int,
    username: str,
    password: str,
    client_count: int,
    connect_stagger_sec: float,
    connect_timeout_sec: float,
    hold_sec: float,
    min_success_rate: float,
) -> AuthLoadMetrics:
    t0 = time.time()
    print(f"\nConnecting {client_count} authenticated MQTT clients through NLB...")
    metrics = run_auth_load(
        mqtt_host,
        mqtt_port,
        username,
        password,
        client_count,
        connect_stagger_sec=connect_stagger_sec,
        connect_timeout_sec=connect_timeout_sec,
        hold_sec=hold_sec,
    )
    duration = time.time() - t0

    print_metrics_table(metrics)

    passed = (
        metrics.failures == 0
        and metrics.connected >= client_count
        and metrics.success_rate_pct >= min_success_rate
    )
    detail_lines = [f"duration={duration:.1f}s target={client_count}"]
    detail_lines.extend(f"{k}: {v}" for k, v in metrics.as_table_rows())
    report.add(
        "Successful authentication under load",
        passed,
        "\n".join(detail_lines),
    )
    return metrics


def main() -> int:
    p = argparse.ArgumentParser(description="Validate EMQX MQTT username/password authentication.")
    p.add_argument("--region", default=os.environ.get("AWS_REGION", "ap-south-1"))
    p.add_argument("--core-ip", default=os.environ.get("EMQX_CORE_IP", ""))
    p.add_argument("--mqtt-host", default=os.environ.get("MQTT_HOST", ""))
    p.add_argument("--mqtt-port", type=int, default=1883)
    p.add_argument("--mqtt-username", default=os.environ.get("MQTT_USERNAME", ""))
    p.add_argument("--mqtt-password", default=os.environ.get("MQTT_PASSWORD", ""))
    p.add_argument("--dashboard-user", default=os.environ.get("EMQX_DASHBOARD_USERNAME", "admin"))
    p.add_argument("--dashboard-password", default=os.environ.get("EMQX_DASHBOARD_PASSWORD", ""))
    p.add_argument("--clients", type=int, default=int(os.environ.get("AUTH_LOAD_CLIENTS", "2000")))
    p.add_argument("--connect-stagger", type=float, default=0.05)
    p.add_argument("--connect-timeout", type=float, default=60.0)
    p.add_argument("--hold-sec", type=float, default=30.0)
    p.add_argument("--min-success-rate", type=float, default=100.0)
    p.add_argument("--skip-load", action="store_true", help="Skip 2K load test (checks only)")
    args = p.parse_args()

    if not args.mqtt_host or not args.core_ip:
        print("Set --mqtt-host and --core-ip", file=sys.stderr)
        return 1
    if not args.mqtt_username or not args.mqtt_password:
        print("Set --mqtt-username and --mqtt-password (or MQTT_USERNAME / MQTT_PASSWORD)", file=sys.stderr)
        return 1
    if not args.dashboard_password:
        print("Set --dashboard-password or EMQX_DASHBOARD_PASSWORD", file=sys.stderr)
        return 1

    report = AuthReport()
    print("=" * 60)
    print("EMQX AUTHENTICATION VALIDATION")
    print("=" * 60)
    print(f"MQTT: {args.mqtt_host}:{args.mqtt_port}")
    print(f"User: {args.mqtt_username}")
    print(f"Load: {args.clients} clients" + (" (skipped)" if args.skip_load else ""))
    print("=" * 60)

    check_auth_backend(report, args.core_ip, args.dashboard_user, args.dashboard_password)
    check_auth_enabled_on_listener(report, args.core_ip, args.dashboard_user, args.dashboard_password)
    check_anonymous_rejected(report, args.mqtt_host, args.mqtt_port)
    check_invalid_credentials(report, args.mqtt_host, args.mqtt_port, args.mqtt_username)
    check_valid_credentials(
        report, args.mqtt_host, args.mqtt_port, args.mqtt_username, args.mqtt_password
    )

    if not args.skip_load:
        check_auth_under_load(
            report,
            args.mqtt_host,
            args.mqtt_port,
            args.mqtt_username,
            args.mqtt_password,
            args.clients,
            args.connect_stagger,
            args.connect_timeout,
            args.hold_sec,
            args.min_success_rate,
        )

    print("\n" + "=" * 60)
    if report.ok():
        print("=== AUTHENTICATION SUMMARY: ALL CHECKS PASSED ===")
        return 0

    print("=== AUTHENTICATION SUMMARY: SOME CHECKS FAILED ===")
    failed = [r.name for r in report.results if not r.passed and not r.skipped]
    print("Failed:", ", ".join(failed))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
