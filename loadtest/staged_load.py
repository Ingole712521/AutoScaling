#!/usr/bin/env python3
"""
High-intensity staged MQTT load test to trigger EMQX replicant autoscaling.

Demo defaults target network > 20 KB/s and CPU > 1% within the first stage.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import threading
import time
from dataclasses import dataclass

import paho.mqtt.client as mqtt


@dataclass(frozen=True)
class Stage:
    clients: int
    duration_sec: int
    label: str


# Aggressive demo profile: heavy load from stage 1 for fast ASG scale-out
DEFAULT_STAGES = [
    Stage(40, 180, "baseline-heavy"),
    Stage(80, 300, "scale-out-2"),
    Stage(120, 300, "scale-out-3"),
    Stage(10, 360, "scale-in"),
]

DEFAULT_PUBLISH_INTERVAL = 0.001
DEFAULT_PAYLOAD_SIZE = 16384
DEFAULT_MESSAGES_PER_BURST = 10
DEFAULT_LOAD_STAGES = ",".join(
    f"{s.clients}:{s.duration_sec}:{s.label}" for s in DEFAULT_STAGES
)


class LoadClient(threading.Thread):
    def __init__(
        self,
        host: str,
        port: int,
        client_id: str,
        topic: str,
        publish_interval_sec: float,
        payload_size: int,
        messages_per_burst: int,
        stop_event: threading.Event,
    ) -> None:
        super().__init__(daemon=True)
        self.host = host
        self.port = port
        self.client_id = client_id
        self.topic = topic
        self.publish_interval_sec = publish_interval_sec
        self.payload = "X" * payload_size
        self.messages_per_burst = messages_per_burst
        self.stop_event = stop_event
        self.published = 0
        self.errors = 0

    def run(self) -> None:
        client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=self.client_id,
            protocol=mqtt.MQTTv311,
        )

        try:
            client.connect(self.host, self.port, keepalive=60)
            client.loop_start()

            seq = 0
            while not self.stop_event.is_set():
                for _ in range(self.messages_per_burst):
                    payload = json.dumps(
                        {
                            "client": self.client_id,
                            "seq": seq,
                            "ts": time.time(),
                            "payload": self.payload,
                        }
                    )
                    result = client.publish(self.topic, payload, qos=0)
                    if result.rc != mqtt.MQTT_ERR_SUCCESS:
                        self.errors += 1
                    else:
                        self.published += 1
                        seq += 1

                time.sleep(self.publish_interval_sec)
        except Exception:
            self.errors += 1
        finally:
            try:
                client.loop_stop()
                client.disconnect()
            except Exception:
                pass


def parse_stages(raw: str) -> list[Stage]:
    stages: list[Stage] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        clients_str, duration_str, *label_parts = part.split(":")
        label = label_parts[0] if label_parts else f"{clients_str}-clients"
        stages.append(
            Stage(
                clients=int(clients_str),
                duration_sec=int(duration_str),
                label=label,
            )
        )
    return stages


def estimate_throughput_bytes_per_sec(
    clients: int,
    publish_interval_sec: float,
    payload_size: int,
    messages_per_burst: int,
) -> int:
    json_overhead = 120
    per_message = payload_size + json_overhead
    if publish_interval_sec <= 0:
        return clients * messages_per_burst * per_message
    return int(clients * messages_per_burst * per_message / publish_interval_sec)


def run_stage(
    host: str,
    port: int,
    stage: Stage,
    topic: str,
    publish_interval_sec: float,
    payload_size: int,
    messages_per_burst: int,
    stage_index: int,
) -> None:
    stop_event = threading.Event()
    threads: list[LoadClient] = []

    est_bps = estimate_throughput_bytes_per_sec(
        stage.clients, publish_interval_sec, payload_size, messages_per_burst
    )

    print(
        f"\n[stage {stage_index}] {stage.label}: "
        f"{stage.clients} clients for {stage.duration_sec}s "
        f"(burst={messages_per_burst}, interval={publish_interval_sec}s, "
        f"payload={payload_size}B, est~{est_bps // 1024} KB/s)"
    )

    for i in range(stage.clients):
        worker = LoadClient(
            host=host,
            port=port,
            client_id=f"load-{stage.label}-{i}",
            topic=topic,
            publish_interval_sec=publish_interval_sec,
            payload_size=payload_size,
            messages_per_burst=messages_per_burst,
            stop_event=stop_event,
        )
        threads.append(worker)
        worker.start()

    deadline = time.time() + stage.duration_sec
    while time.time() < deadline:
        time.sleep(10)
        total_published = sum(t.published for t in threads)
        total_errors = sum(t.errors for t in threads)
        remaining = int(deadline - time.time())
        print(
            f"  ... {stage.clients} clients active, "
            f"published={total_published}, errors={total_errors}, "
            f"remaining={remaining}s"
        )

    stop_event.set()
    for worker in threads:
        worker.join(timeout=5)

    total_published = sum(t.published for t in threads)
    total_errors = sum(t.errors for t in threads)
    print(
        f"[stage {stage_index}] done: published={total_published}, errors={total_errors}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run staged MQTT load against EMQX NLB to trigger autoscaling."
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("MQTT_HOST", ""),
        help="NLB DNS name (or set MQTT_HOST env var).",
    )
    parser.add_argument("--port", type=int, default=int(os.environ.get("MQTT_PORT", "1883")))
    parser.add_argument(
        "--topic",
        default=os.environ.get("MQTT_TOPIC", "loadtest/staged"),
        help="MQTT topic for load messages.",
    )
    parser.add_argument(
        "--publish-interval",
        type=float,
        default=float(os.environ.get("PUBLISH_INTERVAL", str(DEFAULT_PUBLISH_INTERVAL))),
        help="Seconds between publish bursts per client (lower = heavier load).",
    )
    parser.add_argument(
        "--payload-size",
        type=int,
        default=int(os.environ.get("PAYLOAD_SIZE", str(DEFAULT_PAYLOAD_SIZE))),
        help="Payload padding size in bytes.",
    )
    parser.add_argument(
        "--messages-per-burst",
        type=int,
        default=int(os.environ.get("MESSAGES_PER_BURST", str(DEFAULT_MESSAGES_PER_BURST))),
        help="Messages each client publishes per burst.",
    )
    parser.add_argument(
        "--stages",
        default=os.environ.get("LOAD_STAGES", DEFAULT_LOAD_STAGES),
        help="Comma-separated stages as clients:seconds:label.",
    )
    args = parser.parse_args()

    if not args.host:
        print("Error: pass --host or set MQTT_HOST to the NLB DNS name.", file=sys.stderr)
        print("Example: python loadtest/staged_load.py --host your-nlb.elb.amazonaws.com")
        return 1

    stages = parse_stages(args.stages)
    if not stages:
        print("Error: no valid stages configured.", file=sys.stderr)
        return 1

    print("EMQX high-intensity staged load test")
    print(f"  target: {args.host}:{args.port}")
    print(f"  topic:  {args.topic}")
    print(f"  stages: {len(stages)}")
    print(f"  burst:  {args.messages_per_burst} msgs every {args.publish_interval}s")
    print(f"  payload: {args.payload_size} bytes")
    print("  autoscaling target: network > 20 KB/s or CPU > 1%")

    interrupted = threading.Event()

    def handle_signal(_signum, _frame) -> None:
        interrupted.set()
        print("\nStopping load test...")

    signal.signal(signal.SIGINT, handle_signal)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, handle_signal)

    for index, stage in enumerate(stages, start=1):
        if interrupted.is_set():
            break
        run_stage(
            host=args.host,
            port=args.port,
            stage=stage,
            topic=args.topic,
            publish_interval_sec=args.publish_interval,
            payload_size=args.payload_size,
            messages_per_burst=args.messages_per_burst,
            stage_index=index,
        )

    print("\nLoad test finished.")
    print("Check AWS Console -> EC2 Auto Scaling Groups -> desired capacity")
    print("Or CloudWatch -> ASG network in / CPU metrics")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
