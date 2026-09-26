import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
for path in root.rglob("*"):
    if not path.is_file(): continue
    try: text = path.read_text()
    except UnicodeError: continue
    text = re.sub(r"^#!/nix/store/[^/]+/bin/(bash|sh|python3)", r"#!/usr/bin/env \1", text)
    text = re.sub(r"/nix/store/[^/]+-nixos-icons/", sys.argv[2]+"/", text)
    text = re.sub(r"/nix/store/[^/]+-coreutils-[^/]+/", sys.argv[3]+"/", text)
    # Shell fallback paths are evaluated on the running machine.
    text = re.sub(r"/nix/store/[^/]+-omarchy-[^/]+/share/omarchy", "/run/current-system/sw/share/omarchy", text)
    # RetroArch data remains discoverable through the system profile.
    text = re.sub(r"/nix/store/[^/]+-libretro-[^/]+", "/run/current-system/sw", text)
    path.write_text(text)
