"""Watch the keyd virtual keyboard and drive Voxtype hold-to-talk.

keyd maps a lone Control hold to F24 after a short timeout, and keeps
Control chords as Control even after that timeout. This process starts
recording on F24 press and transcribes on F24 release. A non-modifier
key while F24 is held is a Control chord, so recording is cancelled.
Key repeat (value 2) is ignored.
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
# Linux evdev keycodes. oneshotk(control, f24) also emits leftcontrol;
# that must not cancel hold-to-talk.
MODIFIER_KEYS = {
    29,  # KEY_LEFTCTRL
    97,  # KEY_RIGHTCTRL
    42,  # KEY_LEFTSHIFT
    54,  # KEY_RIGHTSHIFT
    56,  # KEY_LEFTALT
    100,  # KEY_RIGHTALT
    125,  # KEY_LEFTMETA
    126,  # KEY_RIGHTMETA
    58,  # KEY_CAPSLOCK
}


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
    if action in ("stop", "cancel") and state != "recording":
        return
    try:
        subprocess.run(["voxtype", "record", action], check=False, timeout=3)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as exc:
        log(f"voxtype record {action} failed: {exc}")


def handle_events(fd):
    f24_held = False
    while True:
        chunk = os.read(fd, EVENT_SIZE)
        if len(chunk) < EVENT_SIZE:
            raise OSError("short read from keyd virtual keyboard")
        _sec, _usec, ev_type, code, value = struct.unpack(EVENT_FORMAT, chunk)
        if ev_type != EV_KEY or value == 2:
            continue
        if code == KEY_F24:
            if value == 1:
                f24_held = True
                record("start")
            elif value == 0:
                f24_held = False
                record("stop")
            continue
        if f24_held and value == 1 and code not in MODIFIER_KEYS:
            record("cancel")


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
