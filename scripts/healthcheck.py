#!/usr/bin/env python3
"""Docker health check for ComfyUI readiness."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

BASE_URL = "http://127.0.0.1:8188"
READY_MARKER = Path("/tmp/comfyui-healthcheck-ready")
REQUIRED_NODES = (
    "AILab_QwenVL",
    "UNETLoader",
    "CLIPLoader",
    "PathchSageAttentionKJ",
    "RIFE VFI",
    "VHS_VideoCombine",
)


def fetch_json(path: str, timeout: int) -> object:
    with urlopen(f"{BASE_URL}{path}", timeout=timeout) as response:
        if response.status != 200:
            raise RuntimeError(f"{path} returned HTTP {response.status}")
        return json.load(response)


def main() -> int:
    try:
        if READY_MARKER.exists():
            fetch_json("/system_stats", timeout=5)
            return 0

        object_info = fetch_json("/object_info", timeout=20)
        if not isinstance(object_info, dict):
            raise RuntimeError("/object_info returned unexpected payload")

        missing = [node for node in REQUIRED_NODES if node not in object_info]
        if missing:
            raise RuntimeError(f"missing required nodes: {', '.join(missing)}")

        READY_MARKER.write_text("ready\n", encoding="ascii")
        return 0
    except (OSError, URLError, ValueError, RuntimeError) as exc:
        print(f"healthcheck failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
