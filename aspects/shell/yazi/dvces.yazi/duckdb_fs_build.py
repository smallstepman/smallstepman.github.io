#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


BUILD_VERSION = 1


def short_hash(value: str) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]


def safe_component(name: str) -> str:
    cleaned = "".join("_" if ch in "/\\\0" else ch for ch in (name or ""))
    cleaned = " ".join(cleaned.split()).strip().rstrip(".")
    if not cleaned or cleaned in {".", ".."}:
        cleaned = "item"
    if cleaned != name:
        cleaned = f"{cleaned}--{short_hash(name)}"
    return cleaned[:120]


def run_query(db_path: Path, sql: str) -> list[dict]:
    cmd = [
        "duckdb",
        "-readonly",
        str(db_path),
        "-json",
        "-c",
        sql,
    ]
    proc = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            proc.stderr.strip() or proc.stdout.strip() or "DuckDB query failed"
        )

    stdout = proc.stdout.strip()
    if not stdout:
        return []
    if stdout == "[{]":
        return []
    return json.loads(stdout)


def as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() == "true"
    return bool(value)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def dump_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True)


def write_json(path: Path, payload: object) -> None:
    write_text(path, dump_json(payload))


def metadata_for(source: Path) -> dict[str, object]:
    stat = source.stat()
    return {
        "build_version": BUILD_VERSION,
        "source": str(source.resolve()),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def is_fresh(root: Path, meta: dict[str, object]) -> bool:
    meta_path = root / ".duckdb_vfs_meta.json"
    summary_path = root / "_summary.txt"
    if not meta_path.exists() or not summary_path.exists():
        return False
    try:
        existing = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return existing == meta


def group_columns(rows: list[dict]) -> dict[tuple[str, str], list[dict]]:
    grouped: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in rows:
        grouped[(row["schema_name"], row["table_name"])].append(row)
    return grouped


def format_columns(columns: list[dict]) -> str:
    lines = ["index\tname\ttype\tnullable\tdefault"]
    for col in columns:
        lines.append(
            "\t".join(
                [
                    str(col.get("column_index", "")),
                    str(col.get("column_name", "")),
                    str(col.get("data_type", "")),
                    "yes" if as_bool(col.get("is_nullable")) else "no",
                    ""
                    if col.get("column_default") is None
                    else str(col.get("column_default")),
                ]
            )
        )
    return "\n".join(lines)


def format_table_meta(row: dict) -> str:
    parts = [
        f"schema: {row['schema_name']}",
        f"name: {row['table_name']}",
        f"rows_estimate: {row.get('estimated_size', '')}",
        f"columns: {row.get('column_count', '')}",
        f"indexes: {row.get('index_count', '')}",
        f"has_primary_key: {as_bool(row.get('has_primary_key'))}",
    ]
    if row.get("comment"):
        parts.extend(["", "comment:", str(row["comment"])])
    return "\n".join(parts)


def format_view_meta(row: dict) -> str:
    parts = [
        f"schema: {row['schema_name']}",
        f"name: {row['view_name']}",
        f"columns: {row.get('column_count', '')}",
        f"is_bound: {as_bool(row.get('is_bound'))}",
    ]
    if row.get("comment"):
        parts.extend(["", "comment:", str(row["comment"])])
    return "\n".join(parts)


def format_function(row: dict) -> str:
    params = []
    if row.get("parameters"):
        params = [
            part.strip()
            for part in str(row["parameters"]).strip("[]").split(",")
            if part.strip()
        ]

    param_types = []
    if row.get("parameter_types"):
        param_types = [
            part.strip()
            for part in str(row["parameter_types"]).strip("[]").split(",")
            if part.strip()
        ]

    signature = []
    for index, param in enumerate(params):
        ptype = param_types[index] if index < len(param_types) else ""
        signature.append(f"{param}: {ptype}".rstrip())

    lines = [
        f"schema: {row['schema_name']}",
        f"name: {row['function_name']}",
        f"type: {row.get('function_type', '')}",
        f"returns: {row.get('return_type') or ''}",
        f"varargs: {row.get('varargs') or ''}",
        "",
        "signature:",
        f"{row['function_name']}({', '.join(signature)})",
    ]

    if row.get("description"):
        lines.extend(["", "description:", str(row["description"])])
    if row.get("comment"):
        lines.extend(["", "comment:", str(row["comment"])])
    if row.get("macro_definition"):
        lines.extend(["", "macro_definition:", str(row["macro_definition"])])
    if row.get("examples"):
        lines.extend(["", "examples:", str(row["examples"])])
    if row.get("categories"):
        lines.extend(["", "categories:", str(row["categories"])])
    if row.get("stability"):
        lines.extend(["", "stability:", str(row["stability"])])

    return "\n".join(lines)


def format_sequence(row: dict) -> str:
    fields = [
        "schema_name",
        "sequence_name",
        "start_value",
        "min_value",
        "max_value",
        "increment_by",
        "cycle",
        "last_value",
    ]
    lines = [f"{field}: {row.get(field, '')}" for field in fields]
    lines[6] = f"cycle: {as_bool(row.get('cycle'))}"
    if row.get("comment"):
        lines.extend(["", "comment:", str(row["comment"])])
    if row.get("sql"):
        lines.extend(["", "sql:", str(row["sql"])])
    return "\n".join(lines)


def format_index(row: dict) -> str:
    lines = [
        f"schema: {row['schema_name']}",
        f"name: {row['index_name']}",
        f"table: {row.get('table_name', '')}",
        f"is_unique: {as_bool(row.get('is_unique'))}",
        f"is_primary: {as_bool(row.get('is_primary'))}",
        f"expressions: {row.get('expressions') or ''}",
    ]
    if row.get("comment"):
        lines.extend(["", "comment:", str(row["comment"])])
    return "\n".join(lines)


def build_tree(source: Path, root: Path) -> None:
    tables = run_query(
        source,
        """
        SELECT schema_name, table_name, comment, has_primary_key, estimated_size, column_count, index_count, sql
        FROM duckdb_tables()
        WHERE internal = false
        ORDER BY schema_name, table_name
        """,
    )
    views = run_query(
        source,
        """
        SELECT schema_name, view_name, comment, column_count, sql, is_bound
        FROM duckdb_views()
        WHERE internal = false
        ORDER BY schema_name, view_name
        """,
    )
    columns = run_query(
        source,
        """
        SELECT schema_name, table_name, column_name, column_index, is_nullable, column_default, data_type
        FROM duckdb_columns()
        WHERE internal = false
        ORDER BY schema_name, table_name, column_index
        """,
    )
    functions = run_query(
        source,
        """
        SELECT schema_name, function_name, function_type, description, comment, return_type,
               CAST(parameters AS VARCHAR) AS parameters,
               CAST(parameter_types AS VARCHAR) AS parameter_types,
               varargs,
               macro_definition,
               CAST(examples AS VARCHAR) AS examples,
               stability,
               CAST(categories AS VARCHAR) AS categories
        FROM duckdb_functions()
        WHERE internal = false
        ORDER BY schema_name, function_name, function_type
        """,
    )
    indexes = run_query(
        source,
        """
        SELECT schema_name, index_name, table_name, comment, is_unique, is_primary, expressions, sql
        FROM duckdb_indexes()
        ORDER BY schema_name, index_name
        """,
    )
    sequences = run_query(
        source,
        """
        SELECT schema_name, sequence_name, comment, start_value, min_value, max_value,
               increment_by, cycle, last_value, sql
        FROM duckdb_sequences()
        ORDER BY schema_name, sequence_name
        """,
    )

    schema_counts: dict[str, Counter] = defaultdict(Counter)
    for row in tables:
        schema_counts[row["schema_name"]]["tables"] += 1
    for row in views:
        schema_counts[row["schema_name"]]["views"] += 1
    for row in functions:
        schema_counts[row["schema_name"]]["functions"] += 1
    for row in indexes:
        schema_counts[row["schema_name"]]["indexes"] += 1
    for row in sequences:
        schema_counts[row["schema_name"]]["sequences"] += 1

    write_text(
        root / "_summary.txt",
        "\n".join(
            [
                f"source: {source.resolve()}",
                "",
                f"schemas: {len(schema_counts)}",
                f"tables: {len(tables)}",
                f"views: {len(views)}",
                f"functions: {len(functions)}",
                f"indexes: {len(indexes)}",
                f"sequences: {len(sequences)}",
                "",
                "This directory is a cached, read-only view generated from a DuckDB file.",
            ]
        ),
    )

    write_text(root / "_source.txt", str(source.resolve()))

    for schema_name, counts in sorted(schema_counts.items()):
        lines = [f"schema: {schema_name}"]
        for key in ("tables", "views", "functions", "indexes", "sequences"):
            lines.append(f"{key}: {counts.get(key, 0)}")
        write_text(
            root / "schemas" / safe_component(schema_name) / "overview.txt",
            "\n".join(lines),
        )

    grouped_columns = group_columns(columns)

    for row in tables:
        schema_dir = (
            root
            / "tables"
            / safe_component(row["schema_name"])
            / safe_component(row["table_name"])
        )
        write_text(schema_dir / "meta.txt", format_table_meta(row))
        write_json(
            schema_dir / "rows.duckdbvfs",
            {
                "kind": "table",
                "source": str(source.resolve()),
                "schema": row["schema_name"],
                "name": row["table_name"],
            },
        )
        write_text(
            schema_dir / "columns.tsv",
            format_columns(
                grouped_columns.get((row["schema_name"], row["table_name"]), [])
            ),
        )
        write_text(
            schema_dir / "create.sql",
            row.get("sql") or f"-- No SQL available for {row['table_name']}",
        )

    for row in views:
        key = (row["schema_name"], row["view_name"])
        schema_dir = (
            root
            / "views"
            / safe_component(row["schema_name"])
            / safe_component(row["view_name"])
        )
        write_text(schema_dir / "meta.txt", format_view_meta(row))
        write_json(
            schema_dir / "rows.duckdbvfs",
            {
                "kind": "view",
                "source": str(source.resolve()),
                "schema": row["schema_name"],
                "name": row["view_name"],
            },
        )
        write_text(
            schema_dir / "columns.tsv", format_columns(grouped_columns.get(key, []))
        )
        write_text(
            schema_dir / "create.sql",
            row.get("sql") or f"-- No SQL available for {row['view_name']}",
        )

    for row in functions:
        filename = f"{safe_component(row['function_name'])}__{safe_component(row.get('function_type') or 'function')}.txt"
        write_text(
            root / "functions" / safe_component(row["schema_name"]) / filename,
            format_function(row),
        )

    for row in indexes:
        schema_dir = root / "indexes" / safe_component(row["schema_name"])
        base = safe_component(row["index_name"])
        write_text(schema_dir / f"{base}.txt", format_index(row))
        if row.get("sql"):
            write_text(schema_dir / f"{base}.sql", row["sql"])

    for row in sequences:
        schema_dir = root / "sequences" / safe_component(row["schema_name"])
        base = safe_component(row["sequence_name"])
        write_text(schema_dir / f"{base}.txt", format_sequence(row))
        if row.get("sql"):
            write_text(schema_dir / f"{base}.sql", row["sql"])


def rebuild(source: Path, root: Path) -> None:
    root.parent.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path(tempfile.mkdtemp(prefix=root.name + ".tmp.", dir=str(root.parent)))
    try:
        build_tree(source, tmp_dir)
        write_text(tmp_dir / ".duckdb_vfs_meta.json", dump_json(metadata_for(source)))
        if root.exists():
            shutil.rmtree(root)
        os.replace(tmp_dir, root)
    except Exception:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a read-only virtual filesystem tree for a DuckDB database."
    )
    parser.add_argument("source")
    parser.add_argument("root")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    source = Path(args.source).expanduser().resolve()
    root = Path(args.root).expanduser().resolve()

    if not source.exists():
        print(f"DuckDB file not found: {source}", file=sys.stderr)
        return 1

    meta = metadata_for(source)
    if not args.refresh and is_fresh(root, meta):
        return 0

    try:
        rebuild(source, root)
    except Exception as exc:  # noqa: BLE001
        print(str(exc), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
