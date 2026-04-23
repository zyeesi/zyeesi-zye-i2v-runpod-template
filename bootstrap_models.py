#!/usr/bin/env python3
"""Download runtime model assets declared in model_manifest.json.

This script is copied into the baked ComfyUI tree and runs at container start.
It is intentionally manifest-driven so new checkpoints, LoRAs, and snapshots
can be added without rewriting the downloader logic.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from huggingface_hub import hf_hub_download, snapshot_download


COMFYUI_DIR = Path(__file__).resolve().parent
MODELS_DIR = COMFYUI_DIR / "models"
MANIFEST_PATH = COMFYUI_DIR / "model_manifest.json"
HF_TOKEN_ENV_VARS = ("HF_TOKEN", "HF_HUB_TOKEN", "HUGGINGFACE_TOKEN")
CIVITAI_TOKEN_ENV_VARS = ("CIVITAI_API_KEY",)


def first_env(names: tuple[str, ...]) -> str | None:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return None


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def existing_file(path: Path) -> bool:
    return path.is_file() and path.stat().st_size > 0


def copy_downloaded_file(source: str | Path, destination: Path) -> None:
    ensure_parent(destination)
    source_path = Path(source)
    with tempfile.NamedTemporaryFile(delete=False, dir=destination.parent) as tmp:
        tmp_path = Path(tmp.name)
    try:
        shutil.copy2(source_path, tmp_path)
        tmp_path.replace(destination)
    finally:
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)


def download_huggingface_file(entry: dict[str, Any], hf_token: str | None) -> str:
    destination = MODELS_DIR / entry["destination"]
    if existing_file(destination):
        return f"skip {entry['name']}: already present at {destination}"

    downloaded = hf_hub_download(
        repo_id=entry["repo_id"],
        filename=entry["filename"],
        token=hf_token,
    )
    copy_downloaded_file(downloaded, destination)
    return f"ok {entry['name']}: downloaded to {destination}"


def download_huggingface_snapshot(entry: dict[str, Any], hf_token: str | None) -> str:
    cache_dir = MODELS_DIR / entry["cache_subdir"]
    cache_dir.mkdir(parents=True, exist_ok=True)
    snapshot_path = snapshot_download(
        repo_id=entry["repo_id"],
        cache_dir=str(cache_dir),
        token=hf_token,
        allow_patterns=entry.get("allow_patterns"),
    )
    return f"ok {entry['name']}: snapshot available at {snapshot_path}"


def civitai_request(version_id: str, token: str) -> Request:
    url = f"https://civitai.com/api/download/models/{version_id}"
    request = Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "zye-i2v-runpod-template"})
    return request


def civitai_request_with_query_token(version_id: str, token: str) -> Request:
    url = f"https://civitai.com/api/download/models/{version_id}?{urlencode({'token': token})}"
    return Request(url, headers={"User-Agent": "zye-i2v-runpod-template"})


def download_civitai_version(entry: dict[str, Any], civitai_token: str | None) -> str:
    destination = MODELS_DIR / entry["destination"]
    if existing_file(destination):
        return f"skip {entry['name']}: already present at {destination}"
    if not civitai_token:
        raise RuntimeError(f"{entry['name']} requires CIVITAI_API_KEY")

    ensure_parent(destination)
    request_builders = (
        lambda: civitai_request(entry["version_id"], civitai_token),
        lambda: civitai_request_with_query_token(entry["version_id"], civitai_token),
    )

    last_error: Exception | None = None
    for build_request in request_builders:
        with tempfile.NamedTemporaryFile(delete=False, dir=destination.parent) as tmp:
            tmp_path = Path(tmp.name)
        try:
            request = build_request()
            with urlopen(request, timeout=300) as response, tmp_path.open("wb") as outfile:
                shutil.copyfileobj(response, outfile)
            tmp_path.replace(destination)
            return f"ok {entry['name']}: downloaded to {destination}"
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            tmp_path.unlink(missing_ok=True)

    assert last_error is not None
    raise RuntimeError(f"{entry['name']} download failed: {last_error}") from last_error


def download_entry(entry: dict[str, Any], hf_token: str | None, civitai_token: str | None) -> str:
    kind = entry["kind"]
    if kind == "huggingface_file":
        return download_huggingface_file(entry, hf_token)
    if kind == "huggingface_snapshot":
        return download_huggingface_snapshot(entry, hf_token)
    if kind == "civitai_version":
        return download_civitai_version(entry, civitai_token)
    raise RuntimeError(f"Unsupported manifest kind: {kind}")


def main() -> int:
    if not MANIFEST_PATH.exists():
        print(f"No model manifest found at {MANIFEST_PATH}, skipping.")
        return 0

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    entries = manifest.get("models", [])
    hf_token = first_env(HF_TOKEN_ENV_VARS)
    civitai_token = first_env(CIVITAI_TOKEN_ENV_VARS)

    print(f"Bootstrapping {len(entries)} model entries from {MANIFEST_PATH}")
    failures: list[str] = []

    for entry in entries:
        try:
            message = download_entry(entry, hf_token, civitai_token)
            print(message)
        except (HTTPError, URLError, OSError, RuntimeError, ValueError) as exc:
            failure = f"error {entry.get('name', '<unnamed>')}: {exc}"
            failures.append(failure)
            print(failure, file=sys.stderr)

    if failures:
        print("Model bootstrap completed with warnings:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
    else:
        print("Model bootstrap completed successfully.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
