#!/usr/bin/env python3
"""Summarize opt-in stdlib build timings from multiple processes."""

import argparse
import json
import math
from pathlib import Path


def summarize(path: Path) -> dict:
    spans = {}
    invalid = 0
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            try:
                event = json.loads(line)
                if not isinstance(event, dict) or event.get("version") != 1:
                    raise ValueError("unsupported record")
                identifier = event["id"]
                phase = event["event"]
                if not isinstance(identifier, str) or not identifier or phase not in ("start", "end"):
                    raise ValueError("invalid identifier or event")
                if not isinstance(event.get("timestamp"), (int, float)) or isinstance(event["timestamp"], bool):
                    raise ValueError("invalid timestamp")
                if not math.isfinite(event["timestamp"]):
                    raise ValueError("invalid timestamp")
                if not isinstance(event.get("kind"), str) or not isinstance(event.get("pid"), int):
                    raise ValueError("invalid build identity")
                if phase == "end":
                    duration = event.get("elapsed_seconds")
                    if not isinstance(duration, (int, float)) or isinstance(duration, bool) or not math.isfinite(duration) or duration < 0:
                        raise ValueError("invalid duration")
                    if not isinstance(event.get("success"), bool):
                        raise ValueError("invalid outcome")
                pair = spans.setdefault(identifier, {})
                if phase in pair:
                    raise ValueError("duplicate event")
                pair[phase] = event
            except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                invalid += 1

    completed = []
    incomplete = 0
    for pair in spans.values():
        start, end = pair.get("start"), pair.get("end")
        if not start or not end:
            incomplete += 1
            continue
        if start["kind"] != end["kind"] or start["pid"] != end["pid"] or end["timestamp"] < start["timestamp"]:
            invalid += 1
            continue
        completed.append((start, end))

    events = []
    for start, end in completed:
        if end["timestamp"] > start["timestamp"]:
            events.extend(((start["timestamp"], 1), (end["timestamp"], -1)))
    active = peak = 0
    for _, delta in sorted(events):
        active += delta
        peak = max(peak, active)
    durations = sorted(end["elapsed_seconds"] for _, end in completed)

    def percentile(fraction):
        return durations[math.ceil(fraction * len(durations)) - 1] if durations else None

    return {
        "completed": len(completed),
        "failed": sum(not end["success"] for _, end in completed),
        "incomplete": incomplete,
        "invalid": invalid,
        "peak_concurrent": peak,
        "duration_seconds_p50": percentile(0.50),
        "duration_seconds_p95": percentile(0.95),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("timings", type=Path, help="JSONL file written by KSWIFTK_STDLIB_TIMINGS")
    args = parser.parse_args()
    print(json.dumps(summarize(args.timings), sort_keys=True))


if __name__ == "__main__":
    main()
