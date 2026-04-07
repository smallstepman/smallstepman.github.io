#!/usr/bin/env python3

from __future__ import annotations

import csv
import io
import os
import shutil
import subprocess
import sys
from pathlib import Path


TIME_ALIASES = {
    "time",
    "ts",
    "timestamp",
    "date",
    "datetime",
}
OPEN_ALIASES = {"open", "o"}
HIGH_ALIASES = {"high", "h"}
LOW_ALIASES = {"low", "l"}
CLOSE_ALIASES = {"close", "c", "adjclose", "adjustedclose"}
VOLUME_ALIASES = {"volume", "vol", "v"}
DIRECT_INPUT_EXTENSIONS = {".csv", ".parquet", ".parq", ".feather", ".arrow", ".ipc"}


def normalize_header(name: str) -> str:
    return "".join(ch for ch in name.strip().lower() if ch.isalnum())


def raw_preview(path: Path, limit: int = 400) -> str:
    try:
        with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
            lines: list[str] = []
            for index, line in enumerate(handle):
                if index >= limit:
                    lines.append("... (truncated)")
                    break
                lines.append(line.rstrip("\n"))
            return "\n".join(lines)
    except Exception as exc:  # noqa: BLE001
        return f"Failed to read CSV preview:\n{exc}"


def find_header(fieldnames: list[str], aliases: set[str]) -> str | None:
    for name in fieldnames:
        if normalize_header(name) in aliases:
            return name
    return None


def find_header_by_priority(fieldnames: list[str], aliases: list[str]) -> str | None:
    normalized_to_name: dict[str, str] = {}
    for name in fieldnames:
        normalized = normalize_header(name)
        if normalized not in normalized_to_name:
            normalized_to_name[normalized] = name

    for alias in aliases:
        if alias in normalized_to_name:
            return normalized_to_name[alias]
    return None


def parse_float(value: str | None, default: float | None = None) -> float | None:
    if value is None:
        return default

    text = value.strip()
    if not text:
        return default

    try:
        return float(text.replace("_", ""))
    except ValueError:
        return default


def parse_int_like(value: str | None) -> int | None:
    if value is None:
        return None

    text = value.strip()
    if not text:
        return None

    try:
        return int(text)
    except ValueError:
        try:
            return int(float(text))
        except ValueError:
            return None


def compute_layout(area_height: int, area_width: int) -> tuple[int, int, int, int]:
    rows = max(8, area_height - 2)
    cols = max(12, area_width - 18)

    reserved_rows = 3
    drawable_rows = max(4, rows - reserved_rows)
    volume_rows = min(6, max(1, drawable_rows // 4))
    price_rows = drawable_rows - volume_rows

    if price_rows < 3:
        volume_rows = max(1, volume_rows - (3 - price_rows))
        price_rows = drawable_rows - volume_rows

    rows = price_rows + volume_rows + reserved_rows
    return rows, cols, price_rows, volume_rows


def resolve_binary() -> str | None:
    home = Path.home()
    configured = os.environ.get("OHLCV_ASCII_BIN")
    candidates = [
        configured,
        str(home / ".cargo" / "target" / "debug" / "ohlcv-ascii"),
        str(home / ".cargo" / "target" / "release" / "ohlcv-ascii"),
        shutil.which("ohlcv-ascii"),
        shutil.which(str(home / ".cargo" / "bin" / "ohlcv-ascii")),
    ]

    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def run_encode(binary: str, path: Path, rows: int, cols: int, price_rows: int, volume_rows: int):
    return subprocess.run(
        [
            binary,
            "encode",
            "--input",
            str(path),
            "--color",
            "--rows",
            str(rows),
            "--cols",
            str(cols),
            "--price-rows",
            str(price_rows),
            "--volume-rows",
            str(volume_rows),
        ],
        text=True,
        capture_output=True,
        check=False,
    )


def convert_for_ohlcv_ascii(path: Path) -> str | None:
    try:
        with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
            reader = csv.DictReader(handle)
            if not reader.fieldnames:
                return None

            fieldnames = list(reader.fieldnames)
            open_key = find_header(fieldnames, OPEN_ALIASES)
            high_key = find_header(fieldnames, HIGH_ALIASES)
            low_key = find_header(fieldnames, LOW_ALIASES)
            close_key = find_header(fieldnames, CLOSE_ALIASES)
            if not all((open_key, high_key, low_key, close_key)):
                return None

            time_key = find_header_by_priority(
                fieldnames,
                ["time", "ts", "timestamp", "date", "datetime"],
            )
            volume_key = find_header(fieldnames, VOLUME_ALIASES)

            rows: list[tuple[int | None, float, float, float, float, float]] = []
            for record in reader:
                open_value = parse_float(record.get(open_key))
                high_value = parse_float(record.get(high_key))
                low_value = parse_float(record.get(low_key))
                close_value = parse_float(record.get(close_key))
                if None in (open_value, high_value, low_value, close_value):
                    continue

                time_value = parse_int_like(record.get(time_key)) if time_key else None
                volume_value = parse_float(record.get(volume_key), 0.0) or 0.0
                rows.append(
                    (
                        time_value,
                        open_value,
                        high_value,
                        low_value,
                        close_value,
                        volume_value,
                    )
                )

            if not rows:
                return None

            real_times = [row[0] for row in rows]
            use_real_times = all(value is not None for value in real_times) and all(
                int(real_times[index]) < int(real_times[index + 1])
                for index in range(len(real_times) - 1)
            )

            out = io.StringIO()
            writer = csv.writer(out, lineterminator="\n")
            writer.writerow(["time", "open", "high", "low", "close", "volume"])

            for index, row in enumerate(rows):
                timestamp = int(row[0]) if use_real_times else index
                writer.writerow([timestamp, row[1], row[2], row[3], row[4], row[5]])

            return out.getvalue()
    except Exception:  # noqa: BLE001
        return None


def build_chart(path: Path, area_height: int, area_width: int) -> str:
    binary = resolve_binary()
    if binary is None:
        return (
            "No runnable `ohlcv-ascii` binary was found.\n"
            "Set OHLCV_ASCII_BIN or install `ohlcv-ascii` on PATH.\n\n"
            + raw_preview(path, limit=120)
        )

    rows, cols, price_rows, volume_rows = compute_layout(area_height, area_width)
    suffix = path.suffix.lower()

    if suffix in DIRECT_INPUT_EXTENSIONS:
        proc = run_encode(binary, path, rows, cols, price_rows, volume_rows)
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.rstrip("\n")

        if suffix != ".csv":
            error = proc.stderr.strip() or "ohlcv-ascii encode failed"
            return f"{error}\n\n{raw_preview(path, limit=120)}"

    csv_payload = convert_for_ohlcv_ascii(path)
    if csv_payload is None:
        return raw_preview(path)

    proc = subprocess.run(
        [
            binary,
            "encode",
            "--input",
            "-",
            "--color",
            "--rows",
            str(rows),
            "--cols",
            str(cols),
            "--price-rows",
            str(price_rows),
            "--volume-rows",
            str(volume_rows),
        ],
        input=csv_payload,
        text=True,
        capture_output=True,
        check=False,
    )

    if proc.returncode == 0 and proc.stdout.strip():
        return proc.stdout.rstrip("\n")

    error = proc.stderr.strip() or "ohlcv-ascii encode failed"
    return f"{error}\n\n{raw_preview(path, limit=120)}"


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: preview.py <path> <area_height> <area_width>")
        return 1

    path = Path(sys.argv[1])
    area_height = max(8, int(sys.argv[2]))
    area_width = max(24, int(sys.argv[3]))
    print(build_chart(path, area_height, area_width))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
