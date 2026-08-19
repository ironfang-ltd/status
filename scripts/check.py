#!/usr/bin/env python3
"""Probe the public Ironfang endpoints and update the data files the status
page reads. Runs from GitHub Actions so measurements come from outside the
Ironfang network."""

import json
import time
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

SERVICES = {
    "website": "https://ironfang.uk/",
    "portal": "https://portal.ironfang.uk/",
    "identity": "https://id.ironfang.uk/healthz",
    "api": "https://api.ironfang.uk/healthz",
}

TIMEOUT = 10
ATTEMPTS = 2
RAW_CAP = 2600  # ~9 days at 5-minute intervals
DAILY_KEEP = 92

DATA = Path(__file__).resolve().parent.parent / "data"


def probe(url: str):
    last_code = 0
    for _ in range(ATTEMPTS):
        start = time.monotonic()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ironfang-status/1.0"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                ms = int((time.monotonic() - start) * 1000)
                if resp.status == 200:
                    return True, ms, resp.status
                last_code = resp.status
        except urllib.error.HTTPError as e:
            last_code = e.code
        except Exception:
            last_code = 0
        time.sleep(2)
    return False, -1, last_code


def load(name, default):
    path = DATA / name
    if path.exists():
        return json.loads(path.read_text())
    return default


def save(name, obj):
    (DATA / name).write_text(json.dumps(obj, separators=(",", ":")) + "\n")


def main():
    DATA.mkdir(exist_ok=True)
    now = datetime.now(timezone.utc)
    stamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    today = now.strftime("%Y-%m-%d")

    current = {"updated": stamp, "services": {}}
    sample = {"t": stamp}
    for key, url in SERVICES.items():
        up, ms, code = probe(url)
        current["services"][key] = {"up": up, "ms": ms, "code": code}
        sample[key] = ms if up else -1

    history = load("history.json", [])
    history.append(sample)
    history = history[-RAW_CAP:]

    daily = load("daily.json", {})
    day = daily.setdefault(today, {k: [0, 0] for k in SERVICES})
    for key in SERVICES:
        day.setdefault(key, [0, 0])
        day[key][1] += 1
        if current["services"][key]["up"]:
            day[key][0] += 1
    cutoff = (now - timedelta(days=DAILY_KEEP)).strftime("%Y-%m-%d")
    daily = {d: v for d, v in sorted(daily.items()) if d >= cutoff}

    save("current.json", current)
    save("history.json", history)
    save("daily.json", daily)

    states = " ".join(
        f"{k}={'up' if v['up'] else 'DOWN'}" for k, v in current["services"].items()
    )
    print(f"{stamp} {states}")


if __name__ == "__main__":
    main()
