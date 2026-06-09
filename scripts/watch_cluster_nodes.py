#!/usr/bin/env python3
"""Poll EMQX cluster API and print node changes (faster than waiting for dashboard UI refresh)."""

from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import datetime

import requests


def login(core_ip: str, user: str, password: str) -> str | None:
    try:
        r = requests.post(
            f"http://{core_ip}:18083/api/v5/login",
            json={"username": user, "password": password},
            timeout=10,
        )
        if r.status_code != 200:
            return None
        return r.json().get("token")
    except requests.RequestException:
        return None


def fetch_nodes(core_ip: str, token: str) -> list[dict]:
    r = requests.get(
        f"http://{core_ip}:18083/api/v5/nodes",
        headers={"Authorization": f"Bearer {token}"},
        timeout=10,
    )
    r.raise_for_status()
    data = r.json()
    if isinstance(data, list):
        return data
    return data.get("data", data.get("nodes", []))


def node_key(node: dict) -> str:
    return str(node.get("node", node.get("node_name", "?")))


def format_node(node: dict) -> str:
    name = node_key(node)
    role = node.get("role", node.get("type", "?"))
    status = node.get("node_status", node.get("status", "?"))
    conns = node.get("live_connections", node.get("connections", "?"))
    return f"{name} status={status} role={role} connections={conns}"


def main() -> int:
    p = argparse.ArgumentParser(description="Watch EMQX cluster nodes via API (live updates).")
    p.add_argument("--core-ip", default=os.environ.get("EMQX_CORE_IP", ""))
    p.add_argument("--user", default=os.environ.get("EMQX_DASHBOARD_USERNAME", "admin"))
    p.add_argument("--password", default=os.environ.get("EMQX_DASHBOARD_PASSWORD", ""))
    p.add_argument("--interval-sec", type=float, default=5.0)
    p.add_argument("--once", action="store_true")
    args = p.parse_args()

    if not args.core_ip or not args.password:
        print("Set --core-ip and --password (or EMQX_CORE_IP / EMQX_DASHBOARD_PASSWORD)", file=sys.stderr)
        return 1

    token = login(args.core_ip, args.user, args.password)
    if not token:
        print("Dashboard login failed", file=sys.stderr)
        return 1

    print(f"Watching cluster nodes at http://{args.core_ip}:18083 (every {args.interval_sec}s)")
    print("Tip: Dashboard Nodes tab may lag — this API view updates first. Click Refresh in UI if needed.")
    print("-" * 60)

    last: dict[str, dict] = {}
    while True:
        try:
            nodes = fetch_nodes(args.core_ip, token)
        except requests.RequestException as exc:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] API error: {exc}")
            time.sleep(args.interval_sec)
            if args.once:
                return 1
            continue

        current = {node_key(n): n for n in nodes}
        ts = datetime.now().strftime("%H:%M:%S")

        if not last:
            print(f"[{ts}] nodes={len(current)}")
            for n in sorted(current.values(), key=node_key):
                print(f"  {format_node(n)}")
        else:
            added = set(current) - set(last)
            removed = set(last) - set(current)
            if added or removed:
                print(f"[{ts}] CHANGE nodes={len(current)} (+{len(added)} -{len(removed)})")
                for name in sorted(added):
                    print(f"  + {format_node(current[name])}")
                for name in sorted(removed):
                    print(f"  - {format_node(last[name])}")
            else:
                print(f"[{ts}] nodes={len(current)} (unchanged)")

        last = current
        if args.once:
            return 0
        time.sleep(args.interval_sec)


if __name__ == "__main__":
    raise SystemExit(main())
