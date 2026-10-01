"""Watch the keyd virtual keyboard and drive Voxtype hold-to-talk.

keyd maps a lone Control hold to F24 after a short timeout, and keeps
Control chords as Control. This process starts recording on F24 press
and transcribes on F24 release. Key repeat (value 2) is ignored.
"""
import glob
import json
import os
import struct
import subprocess
import sys
import time

DEVICE_NAME = "keyd virtual keyboard"
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 0x01
KEY_F24 = 194


def log(message):
    print(f"voxtype-ptt: {message}", file=sys.stderr, flush=True)


def find_device():
    for event in glob.glob("/dev/input/event*"):
        name_file = f"/sys/class/input/{os.path.basename(event)}/device/name"
        try:
            with open(name_file, encoding="utf-8") as fh:
                if fh.read().strip() == DEVICE_NAME:
                    return event
        except OSError:
            continue
    return None


def voxtype_state():
    try:
        raw = subprocess.check_output(
            ["voxtype", "status", "--format", "json"],
            text=True,
            timeout=3,
        )
        data = json.loads(raw)
        return str(data.get("alt") or data.get("class") or "").strip()
    except (
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
        FileNotFoundError,
        json.JSONDecodeError,
        OSError,
    ):
        return ""


def record(action):
    state = voxtype_state()
    if action == "start" and state != "idle":
        return
    if action == "stop" and state != "recording":
        return
    try:
        subprocess.run(["voxtype", "record", action], check=False, timeout=3)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as exc:
        log(f"voxtype record {action} failed: {exc}")


def handle_events(fd):
    while True:
        chunk = os.read(fd, EVENT_SIZE)
        if len(chunk) < EVENT_SIZE:
            raise OSError("short read from keyd virtual keyboard")
        _sec, _usec, ev_type, code, value = struct.unpack(EVENT_FORMAT, chunk)
        if ev_type != EV_KEY or code != KEY_F24:
            continue
        if value == 1:
            record("start")
        elif value == 0:
            record("stop")


def main():
    log("watching keyd virtual keyboard for F24 hold-to-talk")
    while True:
        path = find_device()
        if not path:
            time.sleep(1)
            continue
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError as exc:
            log(f"open {path}: {exc}")
            time.sleep(1)
            continue
        log(f"opened {path}")
        try:
            handle_events(fd)
        except OSError as exc:
            log(f"read {path}: {exc}")
        finally:
            os.close(fd)
        time.sleep(0.5)


if __name__ == "__main__":
    main()
