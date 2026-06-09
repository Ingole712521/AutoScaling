#!/usr/bin/env python3
"""
Authentication during ASG scale-out:
  - Hold authenticated clients active
  - Trigger autoscaling with publish load
  - Validate auth on new nodes, zero new failures, stable cluster
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "loadtest"))

from auth_load import AuthLoadMetrics, SustainedAuthPool, try_connect  # noqa: E402
from staged_load import asg_desired_capacity, log_asg_capacity  # noqa: E402


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str


@dataclass
class ScaleOutReport:
    results: list[CheckResult] = field(default_factory=list)

    def add(self, name: str, passed: bool, detail: str) -> None:
        self.results.append(CheckResult(name, passed, detail))
        tag = "PASS" if passed else "FAIL"
        print(f"[{tag}] {name}")
        for line in detail.splitlines():
            print(f"      {line}")

    def ok(self) -> bool:
        return all(r.passed for r in self.results)


def emqx_login(core_ip: str, user: str, password: str) -> str | None:
    try:
        r = requests.post(
            f"http://{core_ip}:18083/api/v5/login",
            json={"username": user, "password": password},
            timeout=15,
        )
        if r.status_code != 200:
            return None
        return r.json().get("token")
    except requests.RequestException:
        return None


def emqx_cluster_node_count(core_ip: str, dashboard_user: str, dashboard_password: str) -> int:
    token = emqx_login(core_ip, dashboard_user, dashboard_password)
    if not token:
        return 0
    try:
        r = requests.get(
            f"http://{core_ip}:18083/api/v5/nodes",
            headers={"Authorization": f"Bearer {token}"},
            timeout=15,
        )
        r.raise_for_status()
        data = r.json()
        if isinstance(data, list):
            return len(data)
        return len(data.get("data", data.get("nodes", [])))
    except requests.RequestException:
        return 0


def execute_asg_policy(region: str, asg_name: str, policy_name: str) -> tuple[bool, str]:
    try:
        subprocess.check_output(
            [
                "aws", "autoscaling", "execute-policy",
                "--region", region,
                "--auto-scaling-group-name", asg_name,
                "--policy-name", policy_name,
            ],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
        return True, f"executed {policy_name}"
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        return False, str(exc)


def wait_asg_scale_out(
    asg_name: str,
    region: str,
    start_capacity: int,
    target_capacity: int,
    timeout_sec: float,
) -> tuple[bool, int]:
    """Wait until ASG desired capacity increases to target_capacity."""
    if not asg_name:
        return False, start_capacity
    deadline = time.time() + timeout_sec
    last = start_capacity
    while time.time() < deadline:
        cap = asg_desired_capacity(asg_name, region)
        if cap is not None:
            last = cap
            print(f"  ASG desired_capacity={cap} (started={start_capacity}, target>={target_capacity})")
            if cap >= target_capacity and cap > start_capacity:
                return True, cap
            if cap >= target_capacity and start_capacity >= target_capacity:
                return True, cap
        time.sleep(20)
    return last > start_capacity or last >= target_capacity, last


def probe_new_authenticated_clients(
    host: str,
    port: int,
    username: str,
    password: str,
    count: int,
    timeout_sec: float,
) -> tuple[int, int, list[float]]:
    ok = 0
    fail = 0
    latencies: list[float] = []
    for i in range(count):
        passed, _rc, latency = try_connect(
            host, port, username=username, password=password, timeout_sec=timeout_sec
        )
        if passed and latency is not None:
            ok += 1
            latencies.append(latency)
        else:
            fail += 1
        time.sleep(0.1)
    return ok, fail, latencies


def print_scale_out_metrics(
    baseline: AuthLoadMetrics,
    after: AuthLoadMetrics,
    new_connects_ok: int,
    new_connects_fail: int,
    rep_asg_start: int,
    rep_asg_end: int,
    core_asg_start: int,
    core_asg_end: int,
    cluster_nodes: int,
) -> None:
    print("")
    print("=" * 60)
    print("AUTHENTICATION DURING SCALE-OUT — METRICS")
    print("=" * 60)
    rows = [
        ("Authentication Method", "Username / Password"),
        ("Baseline Authenticated Clients (held)", str(baseline.connected)),
        ("Clients Live After Scale-Out", str(after.connected)),
        ("Auth Failures (baseline → after delta)", f"{after.failures - baseline.failures}"),
        ("Unexpected Disconnects (delta)", f"{after.disconnects - baseline.disconnects}"),
        ("New-Node Auth Probes OK / Fail", f"{new_connects_ok} / {new_connects_fail}"),
        ("Replicant ASG (start → end)", f"{rep_asg_start} → {rep_asg_end}"),
        ("Core ASG (start → end)", f"{core_asg_start} → {core_asg_end}"),
        ("Cluster Nodes Visible", str(cluster_nodes)),
    ]
    print(f"{'Metric':<40} {'Value':>18}")
    print("-" * 60)
    for label, value in rows:
        print(f"{label:<40} {value:>18}")
    print("=" * 60)


def main() -> int:
    p = argparse.ArgumentParser(description="Validate MQTT auth during ASG scale-out.")
    p.add_argument("--region", default=os.environ.get("AWS_REGION", "ap-south-1"))
    p.add_argument("--project", default=os.environ.get("PROJECT_NAME", "emqx-prod"))
    p.add_argument("--core-ip", default=os.environ.get("EMQX_CORE_IP", ""))
    p.add_argument("--mqtt-host", default=os.environ.get("MQTT_HOST", ""))
    p.add_argument("--mqtt-port", type=int, default=1883)
    p.add_argument("--mqtt-username", default=os.environ.get("MQTT_USERNAME", ""))
    p.add_argument("--mqtt-password", default=os.environ.get("MQTT_PASSWORD", ""))
    p.add_argument("--asg-name", default=os.environ.get("ASG_NAME", ""), help="Replicant ASG name")
    p.add_argument("--core-asg-name", default=os.environ.get("CORE_ASG_NAME", ""), help="Core ASG name")
    p.add_argument("--target-core-capacity", type=int, default=2, help="Wait for core ASG desired capacity")
    p.add_argument("--dashboard-user", default=os.environ.get("EMQX_DASHBOARD_USERNAME", "admin"))
    p.add_argument("--dashboard-password", default=os.environ.get("EMQX_DASHBOARD_PASSWORD", ""))
    p.add_argument("--baseline-clients", type=int, default=50, help="Conn-only auth clients held during scale-out")
    p.add_argument("--load-clients", type=int, default=100, help="Publish clients to trigger scale-out")
    p.add_argument("--target-asg-capacity", type=int, default=2, help="Wait for this ASG desired capacity")
    p.add_argument("--new-node-probes", type=int, default=30, help="Fresh auth connects after scale-out")
    p.add_argument("--scale-timeout-sec", type=float, default=900)
    p.add_argument("--warmup-after-scale-sec", type=float, default=90, help="Wait for new node bootstrap")
    args = p.parse_args()

    if not args.mqtt_host or not args.core_ip:
        print("Set --mqtt-host and --core-ip", file=sys.stderr)
        return 1
    if not args.mqtt_username or not args.mqtt_password:
        print("Set MQTT_USERNAME / MQTT_PASSWORD", file=sys.stderr)
        return 1
    if not args.asg_name:
        print("Set --asg-name or ASG_NAME", file=sys.stderr)
        return 1

    report = ScaleOutReport()
    print("=" * 60)
    print("AUTHENTICATION DURING SCALE-OUT")
    print("=" * 60)
    print(f"MQTT: {args.mqtt_host}:{args.mqtt_port}")
    core_asg = args.core_asg_name or args.asg_name.replace("replicants", "core")
    print(f"Replicant ASG: {args.asg_name} → target>={args.target_asg_capacity}")
    print(f"Core ASG:      {core_asg} → target>={args.target_core_capacity}")
    print("=" * 60)

    ok, _, _ = try_connect(
        args.mqtt_host, args.mqtt_port,
        username=args.mqtt_username, password=args.mqtt_password,
    )
    if not ok:
        report.add("Preflight authenticated connect", False, "Cannot connect with MQTT credentials")
        return 1
    report.add("Preflight authenticated connect", True, "Credentials accepted via NLB")

    rep_start = asg_desired_capacity(args.asg_name, args.region) or 1
    rep_target = max(args.target_asg_capacity, rep_start + 1)
    core_start = asg_desired_capacity(core_asg, args.region) or 1 if core_asg else 1
    core_target = max(args.target_core_capacity, core_start + 1) if core_asg else core_start
    log_asg_capacity(args.asg_name, args.region, "replicants before test")
    if core_asg:
        log_asg_capacity(core_asg, args.region, "core before test")
    print(f"  Replicant scale target: {rep_start} → >={rep_target}")
    if core_asg:
        print(f"  Core scale target:      {core_start} → >={core_target}")
    cluster_start = emqx_cluster_node_count(args.core_ip, args.dashboard_user, args.dashboard_password)

    pool = SustainedAuthPool(
        args.mqtt_host,
        args.mqtt_port,
        args.mqtt_username,
        args.mqtt_password,
    )

    print(f"\n[Phase 1] Starting {args.baseline_clients} authenticated conn-only clients...")
    pool.start(args.baseline_clients, stagger_sec=0.08, conn_only=True)
    if not pool.wait_connected(max(1, int(args.baseline_clients * 0.9)), timeout_sec=120):
        pool.stop()
        report.add(
            "Authenticated clients active",
            False,
            f"Only {pool.live_count()}/{args.baseline_clients} connected",
        )
        return 1

    baseline_snap = pool.snapshot()
    report.add(
        "Authenticated clients active",
        True,
        f"live={baseline_snap.connected} auth_failures={baseline_snap.failures}",
    )

    print(f"\n[Phase 2] Adding {args.load_clients} authenticated publish clients to trigger scale-out...")
    pool.start(args.load_clients, stagger_sec=0.05, conn_only=False)
    pool.wait_connected(
        args.baseline_clients + max(1, int(args.load_clients * 0.7)),
        timeout_sec=180,
    )

    mid_snap = pool.snapshot()
    print(f"  Load clients live={mid_snap.connected} failures={mid_snap.failures}")

    print(f"\n[Phase 3] Waiting for replicant ASG scale-out (target>={rep_target})...")
    rep_wait = max(120, args.scale_timeout_sec / 2)
    rep_scaled, rep_end = wait_asg_scale_out(
        args.asg_name,
        args.region,
        rep_start,
        rep_target,
        rep_wait,
    )
    if not rep_scaled and rep_end < rep_target:
        policy = f"{args.project}-replicants-scale-out-nlb"
        print(f"  Triggering replicant scale-out policy: {policy}")
        execute_asg_policy(args.region, args.asg_name, policy)
        rep_scaled, rep_end = wait_asg_scale_out(
            args.asg_name,
            args.region,
            rep_start,
            rep_target,
            rep_wait,
        )
    report.add(
        "Replicant autoscaling event triggered",
        rep_scaled or rep_end >= rep_target,
        f"replicant ASG {rep_start} → {rep_end} (target>={rep_target})",
    )

    core_scaled = False
    core_end = core_start
    if core_asg and core_target > core_start:
        print(f"\n[Phase 3b] Waiting for core ASG scale-out (target>={core_target})...")
        core_wait = min(args.scale_timeout_sec, 300)
        core_scaled, core_end = wait_asg_scale_out(
            core_asg,
            args.region,
            core_start,
            core_target,
            core_wait,
        )
        if not core_scaled and core_end < core_target:
            policy = f"{args.project}-core-scale-out-cpu"
            print(f"  Triggering core scale-out policy: {policy}")
            execute_asg_policy(args.region, core_asg, policy)
            core_scaled, core_end = wait_asg_scale_out(
                core_asg,
                args.region,
                core_start,
                core_target,
                core_wait,
            )
        report.add(
            "Core autoscaling event triggered",
            core_scaled or core_end >= core_target,
            f"core ASG {core_start} → {core_end} (target>={core_target})",
        )
    elif core_asg:
        report.add(
            "Core autoscaling event triggered",
            core_end >= core_target or core_start >= args.target_core_capacity,
            f"core ASG {core_start} → {core_end} (target>={core_target})",
        )

    if rep_scaled or rep_end >= rep_target or core_scaled:
        print(f"  Scale-out detected. Waiting {args.warmup_after_scale_sec}s for new node bootstrap...")
        time.sleep(args.warmup_after_scale_sec)

    after_scale_snap = pool.snapshot()
    failure_delta = after_scale_snap.failures - baseline_snap.failures
    disconnect_delta = after_scale_snap.disconnects - baseline_snap.disconnects

    report.add(
        "No increase in authentication failures (held clients)",
        failure_delta == 0 and disconnect_delta == 0,
        "\n".join([
            f"auth_failures delta={failure_delta}",
            f"disconnects delta={disconnect_delta}",
            f"baseline_live={baseline_snap.connected} current_live={after_scale_snap.connected}",
        ]),
    )

    print(f"\n[Phase 4] Probing {args.new_node_probes} fresh authenticated connects (new NLB targets)...")
    probe_ok, probe_fail, probe_lat = probe_new_authenticated_clients(
        args.mqtt_host,
        args.mqtt_port,
        args.mqtt_username,
        args.mqtt_password,
        args.new_node_probes,
        timeout_sec=20.0,
    )
    lat_line = "n/a"
    if probe_lat:
        avg = sum(probe_lat) / len(probe_lat)
        lat_line = f"avg={avg:.1f}ms ({len(probe_lat)} samples)"
    report.add(
        "Successful authentication on new nodes",
        probe_fail == 0 and probe_ok == args.new_node_probes,
        f"probes_ok={probe_ok} probes_fail={probe_fail} latency={lat_line}",
    )

    cluster_end = emqx_cluster_node_count(args.core_ip, args.dashboard_user, args.dashboard_password)
    min_nodes = rep_end + core_end
    cluster_stable = cluster_end >= min_nodes and cluster_end >= cluster_start
    report.add(
        "Stable cluster behavior",
        cluster_stable,
        "\n".join([
            f"cluster_nodes={cluster_end} (was {cluster_start})",
            f"expected>={min_nodes} ({core_end} core + {rep_end} replicants)",
            f"held_clients_live={after_scale_snap.connected}",
        ]),
    )

    print_scale_out_metrics(
        baseline_snap,
        after_scale_snap,
        probe_ok,
        probe_fail,
        rep_start,
        rep_end,
        core_start,
        core_end,
        cluster_end,
    )

    pool.stop()

    print("\n" + "=" * 60)
    if report.ok():
        print("=== AUTH SCALE-OUT SUMMARY: ALL CHECKS PASSED ===")
        return 0

    print("=== AUTH SCALE-OUT SUMMARY: SOME CHECKS FAILED ===")
    print("Failed:", ", ".join(r.name for r in report.results if not r.passed))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
