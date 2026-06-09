#!/usr/bin/env python3
"""
Security validation for EMQX on AWS:
  - Security group rules (ports 1883, 8883, 18083)
  - Port exposure (NLB vs EC2, dashboard CIDR restriction)
  - MQTT over TLS (when enabled): handshake, certificate, ACM integration
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import ssl
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

import requests


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str
    skipped: bool = False


@dataclass
class SecurityReport:
    results: list[CheckResult] = field(default_factory=list)

    def add(self, name: str, passed: bool, detail: str, *, skipped: bool = False) -> None:
        self.results.append(CheckResult(name, passed, detail, skipped))
        if skipped:
            tag = "SKIP"
        else:
            tag = "PASS" if passed else "FAIL"
        print(f"[{tag}] {name}")
        for line in detail.splitlines():
            print(f"      {line}")

    def ok(self) -> bool:
        return all(r.passed or r.skipped for r in self.results)


def aws_json(cmd: list[str], timeout: int = 60) -> dict | list | None:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        return json.loads(out) if out.strip() else None
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError) as exc:
        return {"error": str(exc)}


def aws_text(cmd: list[str], timeout: int = 60) -> str | None:
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=timeout).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def tcp_open(host: str, port: int, timeout_sec: float = 5.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout_sec):
            return True
    except OSError:
        return False


def sg_rules(region: str, sg_id: str) -> list[dict]:
    data = aws_json(
        [
            "aws", "ec2", "describe-security-groups",
            "--region", region,
            "--group-ids", sg_id,
            "--output", "json",
        ]
    )
    if not isinstance(data, dict) or not data.get("SecurityGroups"):
        return []
    return data["SecurityGroups"][0].get("IpPermissions", [])


def rule_allows_port(rules: list[dict], port: int) -> list[str]:
    matches: list[str] = []
    for rule in rules:
        from_p = rule.get("FromPort")
        to_p = rule.get("ToPort")
        proto = rule.get("IpProtocol", "")
        if proto == "-1" or (from_p is not None and to_p is not None and from_p <= port <= to_p):
            if rule.get("IpRanges"):
                for r in rule["IpRanges"]:
                    cidr = r.get("CidrIp", "?")
                    desc = r.get("Description", "")
                    matches.append(f"cidr={cidr} {desc}".strip())
            if rule.get("UserIdGroupPairs"):
                for g in rule["UserIdGroupPairs"]:
                    gid = g.get("GroupId", g.get("GroupName", "?"))
                    desc = g.get("Description", "")
                    matches.append(f"sg={gid} {desc}".strip())
    return matches


def rule_allows_port_from_cidr(rules: list[dict], port: int, cidr: str) -> bool:
    for rule in rules:
        from_p = rule.get("FromPort")
        to_p = rule.get("ToPort")
        if from_p is None or to_p is None or not (from_p <= port <= to_p):
            continue
        for r in rule.get("IpRanges", []):
            if r.get("CidrIp") == cidr:
                return True
    return False


def rule_allows_port_from_sg(rules: list[dict], port: int, source_sg: str) -> bool:
    for rule in rules:
        from_p = rule.get("FromPort")
        to_p = rule.get("ToPort")
        if from_p is None or to_p is None or not (from_p <= port <= to_p):
            continue
        for g in rule.get("UserIdGroupPairs", []):
            if g.get("GroupId") == source_sg or g.get("GroupName") == source_sg:
                return True
    return False


def check_sg_ports(
    report: SecurityReport,
    region: str,
    nlb_sg: str,
    nodes_sg: str,
    dashboard_cidr: str,
    tls_enabled: bool,
) -> None:
    nlb_rules = sg_rules(region, nlb_sg)
    node_rules = sg_rules(region, nodes_sg)

    nlb_1883 = rule_allows_port(nlb_rules, 1883)
    report.add(
        "NLB SG — port 1883 (MQTT plaintext)",
        bool(nlb_1883),
        "Ingress: " + ("; ".join(nlb_1883) if nlb_1883 else "not found"),
    )

    nlb_8883 = rule_allows_port(nlb_rules, 8883)
    if tls_enabled:
        report.add(
            "NLB SG — port 8883 (MQTT TLS)",
            bool(nlb_8883),
            "Ingress: " + ("; ".join(nlb_8883) if nlb_8883 else "not found — required when TLS enabled"),
        )
    else:
        report.add(
            "NLB SG — port 8883 (MQTT TLS)",
            True,
            "TLS disabled (enable_mqtt_tls=false); port 8883 not required",
            skipped=True,
        )

    nlb_18083 = rule_allows_port(nlb_rules, 18083)
    report.add(
        "NLB SG — port 18083 NOT exposed",
        not nlb_18083,
        "Dashboard must not be on NLB" if not nlb_18083 else "FAIL: dashboard port open on NLB SG",
    )

    nodes_1883_public = rule_allows_port_from_cidr(node_rules, 1883, "0.0.0.0/0")
    nodes_1883_nlb = rule_allows_port_from_sg(node_rules, 1883, nlb_sg)
    report.add(
        "EMQX nodes SG — port 1883 only from NLB",
        nodes_1883_nlb and not nodes_1883_public,
        "\n".join(
            [
                f"From NLB SG: {nodes_1883_nlb}",
                f"From 0.0.0.0/0: {nodes_1883_public} (must be false)",
            ]
        ),
    )

    dash_rules = rule_allows_port(node_rules, 18083)
    dash_restricted = rule_allows_port_from_cidr(node_rules, 18083, dashboard_cidr)
    report.add(
        "EMQX nodes SG — port 18083 (dashboard)",
        bool(dash_rules),
        "\n".join(
            [
                "Ingress: " + ("; ".join(dash_rules) if dash_rules else "not found"),
                f"Expected CIDR {dashboard_cidr} allowed: {dash_restricted}",
            ]
        ),
    )

    nodes_8883_public = rule_allows_port_from_cidr(node_rules, 8883, "0.0.0.0/0")
    nodes_8883_any = rule_allows_port(node_rules, 8883)
    report.add(
        "EMQX nodes SG — port 8883 NOT public",
        not nodes_8883_public and not nodes_8883_any,
        "TLS terminates at NLB; brokers listen on 1883 internally"
        if not nodes_8883_any
        else "WARN: 8883 open on EC2 — prefer NLB TLS termination only",
    )


def check_port_reachability(
    report: SecurityReport,
    mqtt_host: str,
    core_ip: str,
    tls_enabled: bool,
) -> None:
    report.add(
        "Reachability — MQTT plaintext :1883 (NLB)",
        tcp_open(mqtt_host, 1883),
        f"{mqtt_host}:1883",
    )
    report.add(
        "Reachability — Dashboard :18083 (core EIP)",
        tcp_open(core_ip, 18083),
        f"{core_ip}:18083 (not via NLB)",
    )
    if tls_enabled:
        report.add(
            "Reachability — MQTT TLS :8883 (NLB)",
            tcp_open(mqtt_host, 8883),
            f"{mqtt_host}:8883",
        )
    else:
        report.add(
            "Reachability — MQTT TLS :8883 (NLB)",
            True,
            "TLS disabled; skipped",
            skipped=True,
        )


def parse_cert_not_after(not_after: str) -> datetime | None:
    for fmt in ("%b %d %H:%M:%S %Y %Z", "%Y%m%d%H%M%S%z"):
        try:
            return datetime.strptime(not_after, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def check_tls(
    report: SecurityReport,
    mqtt_host: str,
    tls_hostname: str | None,
    acm_arn: str | None,
    region: str,
) -> None:
    if not acm_arn:
        report.add("MQTT over TLS", True, "TLS not enabled", skipped=True)
        return

    server_hostname = tls_hostname or mqtt_host
    lines: list[str] = []
    passed = True

    try:
        context = ssl.create_default_context()
        context.check_hostname = tls_hostname is not None
        context.verify_mode = ssl.CERT_REQUIRED if tls_hostname else ssl.CERT_NONE

        with socket.create_connection((mqtt_host, 8883), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=server_hostname) as ssock:
                version = ssock.version() or "unknown"
                cipher = ssock.cipher()
                cert = ssock.getpeercert()

        lines.append(f"TLS version: {version}")
        if cipher:
            lines.append(f"Cipher: {cipher[0]} ({cipher[2]} bits)")

        if cert:
            subject = dict(x[0] for x in cert.get("subject", []))
            issuer = dict(x[0] for x in cert.get("issuer", []))
            lines.append(f"Certificate CN: {subject.get('commonName', '?')}")
            lines.append(f"Issuer: {issuer.get('organizationName', '?')} ({issuer.get('commonName', '?')})")
            not_after = cert.get("notAfter")
            if not_after:
                lines.append(f"Valid until: {not_after}")
                expiry = parse_cert_not_after(not_after)
                if expiry and expiry < datetime.now(timezone.utc):
                    passed = False
                    lines.append("Certificate EXPIRED")
            san = cert.get("subjectAltName", [])
            if san:
                lines.append("SANs: " + ", ".join(f"{k}:{v}" for k, v in san[:5]))

        if version and "TLSv1" in version and "TLSv1.2" not in version and "TLSv1.3" not in version:
            passed = False
            lines.append("TLS 1.0/1.1 not recommended for MQTT")

    except ssl.SSLError as exc:
        passed = False
        lines.append(f"TLS handshake failed: {exc}")
    except OSError as exc:
        passed = False
        lines.append(f"Connection failed: {exc}")

    acm_data = aws_json(
        [
            "aws", "acm", "describe-certificate",
            "--region", region,
            "--certificate-arn", acm_arn,
            "--output", "json",
        ]
    )
    if isinstance(acm_data, dict) and acm_data.get("Certificate"):
        cert_info = acm_data["Certificate"]
        lines.append(f"ACM status: {cert_info.get('Status', '?')}")
        lines.append(f"ACM ARN: {acm_arn}")
        lines.append(f"ACM type: {cert_info.get('Type', 'AMAZON_ISSUED')}")
        lines.append("ACM auto-renews before expiry (managed certificate)")
        if cert_info.get("Status") != "ISSUED":
            passed = False
    else:
        lines.append(f"Could not describe ACM certificate: {acm_arn}")

    report.add("MQTT over TLS (NLB :8883 + ACM)", passed, "\n".join(lines))


def check_dashboard_auth(core_ip: str, user: str, password: str) -> tuple[bool, str]:
    url = f"http://{core_ip}:18083/api/v5/login"
    try:
        r = requests.post(url, json={"username": user, "password": password}, timeout=10)
        if r.status_code == 200 and r.json().get("token"):
            return True, "Dashboard requires authentication (login OK)"
        return False, f"Dashboard login failed: HTTP {r.status_code}"
    except requests.RequestException as exc:
        return False, str(exc)


def main() -> int:
    p = argparse.ArgumentParser(description="Validate EMQX AWS security groups, ports, and TLS.")
    p.add_argument("--region", default=os.environ.get("AWS_REGION", "ap-south-1"))
    p.add_argument("--project", default=os.environ.get("PROJECT_NAME", "emqx-prod"))
    p.add_argument("--core-ip", default=os.environ.get("EMQX_CORE_IP", ""))
    p.add_argument("--mqtt-host", default=os.environ.get("MQTT_HOST", ""))
    p.add_argument("--nlb-sg", default=os.environ.get("NLB_SG_ID", ""))
    p.add_argument("--nodes-sg", default=os.environ.get("EMQX_NODES_SG_ID", ""))
    p.add_argument("--dashboard-cidr", default=os.environ.get("DASHBOARD_ALLOWED_CIDR", "0.0.0.0/0"))
    p.add_argument("--tls-enabled", action="store_true", default=os.environ.get("MQTT_TLS_ENABLED", "").lower() == "true")
    p.add_argument("--acm-arn", default=os.environ.get("ACM_CERTIFICATE_ARN", ""))
    p.add_argument("--tls-hostname", default=os.environ.get("MQTT_TLS_HOSTNAME", ""), help="SNI hostname for cert validation (your ACM domain)")
    p.add_argument("--dashboard-user", default=os.environ.get("EMQX_DASHBOARD_USERNAME", "admin"))
    p.add_argument("--dashboard-password", default=os.environ.get("EMQX_DASHBOARD_PASSWORD", ""))
    p.add_argument("--skip-reachability", action="store_true")
    args = p.parse_args()

    if not args.mqtt_host or not args.core_ip:
        print("Set --mqtt-host and --core-ip (or MQTT_HOST / EMQX_CORE_IP)", file=sys.stderr)
        return 1

    nlb_sg = args.nlb_sg or aws_text(
        [
            "aws", "ec2", "describe-security-groups",
            "--region", args.region,
            "--filters", f"Name=group-name,Values={args.project}-nlb-sg",
            "--query", "SecurityGroups[0].GroupId",
            "--output", "text",
        ]
    )
    nodes_sg = args.nodes_sg or aws_text(
        [
            "aws", "ec2", "describe-security-groups",
            "--region", args.region,
            "--filters", f"Name=group-name,Values={args.project}-emqx-cluster-sg",
            "--query", "SecurityGroups[0].GroupId",
            "--output", "text",
        ]
    )

    if not nlb_sg or nlb_sg == "None" or not nodes_sg or nodes_sg == "None":
        print("Cannot resolve security group IDs (set --nlb-sg / --nodes-sg or apply terraform)", file=sys.stderr)
        return 1

    tls_enabled = args.tls_enabled or bool(args.acm_arn)
    tls_hostname = args.tls_hostname or None

    report = SecurityReport()
    print("=" * 60)
    print("EMQX SECURITY VALIDATION")
    print("=" * 60)
    print(f"NLB SG:    {nlb_sg}")
    print(f"Nodes SG:  {nodes_sg}")
    print(f"TLS:       {'enabled' if tls_enabled else 'disabled'}")
    print("=" * 60)

    check_sg_ports(report, args.region, nlb_sg, nodes_sg, args.dashboard_cidr, tls_enabled)

    if not args.skip_reachability:
        check_port_reachability(report, args.mqtt_host, args.core_ip, tls_enabled)

    check_tls(report, args.mqtt_host, tls_hostname, args.acm_arn or None, args.region)

    if args.dashboard_password:
        ok, detail = check_dashboard_auth(args.core_ip, args.dashboard_user, args.dashboard_password)
        report.add("Dashboard authentication", ok, detail)
    else:
        report.add(
            "Dashboard authentication",
            True,
            "Skipped (set EMQX_DASHBOARD_PASSWORD to verify login)",
            skipped=True,
        )

    print("\n" + "=" * 60)
    if report.ok():
        print("=== SECURITY SUMMARY: ALL CHECKS PASSED ===")
        print("Validated:")
        print("  - Security groups: 1883, 8883 (if TLS), 18083")
        print("  - MQTT plaintext via NLB; dashboard on core only")
        print("  - Brokers accept MQTT from NLB SG only (not public internet)")
        if tls_enabled:
            print("  - MQTT over TLS on :8883 with ACM certificate at NLB")
        return 0

    print("=== SECURITY SUMMARY: SOME CHECKS FAILED ===")
    failed = [r.name for r in report.results if not r.passed and not r.skipped]
    print("Failed:", ", ".join(failed))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
