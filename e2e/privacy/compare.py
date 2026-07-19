#!/usr/bin/env python3
# Copyright 2024 Ant Group Co., Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Compare direct component results with E2E backend results.

Usage:
    python e2e/privacy/compare.py --direct e2e/privacy/results/direct \
        --e2e e2e/privacy/results/e2e
"""

import argparse
import json
import sys
from pathlib import Path

import pandas as pd


def load_summary(result_dir: Path, comp_name: str) -> dict:
    summary_path = result_dir / comp_name / "summary.json"
    with open(summary_path) as f:
        return json.load(f)


def _read_table(path: Path) -> pd.DataFrame:
    """Read a component table output, supporting CSV or ORC on disk."""
    suffix = path.suffix.lower()
    if suffix == ".orc" or (
        suffix == ".csv" and path.read_bytes()[:4] == b"ORC\n"
    ):
        import pyarrow.orc as orc

        return orc.ORCFile(path).read().to_pandas()
    return pd.read_csv(path)


def compare_csv(direct_csv: Path, e2e_csv: Path, comp_name: str) -> bool:
    direct_df = _read_table(direct_csv)
    e2e_df = _read_table(e2e_csv)

    # Normalize column order: sort columns by name for comparison.
    direct_df = direct_df.reindex(sorted(direct_df.columns), axis=1)
    e2e_df = e2e_df.reindex(sorted(e2e_df.columns), axis=1)

    if direct_df.shape != e2e_df.shape:
        print(f"  {comp_name}: table shape mismatch {direct_df.shape} vs {e2e_df.shape}")
        return False

    if list(direct_df.columns) != list(e2e_df.columns):
        print(f"  {comp_name}: table columns mismatch")
        print(f"    direct: {list(direct_df.columns)}")
        print(f"    e2e:    {list(e2e_df.columns)}")
        return False

    try:
        pd.testing.assert_frame_equal(direct_df, e2e_df, check_dtype=False)
    except AssertionError as e:
        print(f"  {comp_name}: table content mismatch\n{e}")
        return False
    return True


def compare_report(direct_report: Path, e2e_report: Path, comp_name: str) -> bool:
    with open(direct_report) as f:
        direct = json.load(f)
    with open(e2e_report) as f:
        e2e = json.load(f)

    # E2E report meta has a different envelope than direct protobuf dump.
    # Compare the tab names and the public rows for the key tab.
    direct_tabs = {t["name"]: t for t in direct.get("tabs", [])}
    e2e_tabs = {t["name"]: t for t in e2e.get("tabs", [])}

    if set(direct_tabs.keys()) != set(e2e_tabs.keys()):
        print(f"  {comp_name}: report tab names differ")
        print(f"    direct: {sorted(direct_tabs.keys())}")
        print(f"    e2e:    {sorted(e2e_tabs.keys())}")
        return False

    for name, d_tab in direct_tabs.items():
        e_tab = e2e_tabs[name]
        # The E2E meta mirrors headers/rows but rows are dicts of strings.
        d_rows = d_tab.get("rows", [])
        e_rows = e_tab.get("rows", [])
        if len(d_rows) != len(e_rows):
            print(f"  {comp_name}: report tab '{name}' row count mismatch")
            return False
        for i, (dr, er) in enumerate(zip(d_rows, e_rows)):
            # Convert direct protobuf Attribute dicts to plain strings for comparison.
            d_plain = {k: _attr_to_str(v) for k, v in dr.items()}
            if d_plain != er:
                print(f"  {comp_name}: report tab '{name}' row {i} mismatch")
                print(f"    direct: {d_plain}")
                print(f"    e2e:    {er}")
                return False
    return True


def _attr_to_str(v) -> str:
    """Convert a protobuf Attribute JSON value to a string."""
    if isinstance(v, dict):
        # Attribute one-of: s, i64, f, b, ss, i64s, fs, bs
        for key in ["s", "i64", "f", "b"]:
            if key in v:
                return str(v[key])
        for key in ["ss", "i64s", "fs", "bs"]:
            if key in v:
                return json.dumps(v[key], ensure_ascii=False)
    return str(v)


def compare_component(direct_dir: Path, e2e_dir: Path, comp_key: str) -> bool:
    direct_summary = load_summary(direct_dir, comp_key)
    e2e_summary = load_summary(e2e_dir, comp_key)
    ok = True

    comp_name = direct_summary.get("component", {}).get("name", comp_key)
    for key, direct_rel in direct_summary.items():
        if key in ("component", "attrs"):
            continue
        e2e_rel = e2e_summary.get(key)
        if e2e_rel is None:
            print(f"  {comp_name}: missing {key} in E2E results")
            ok = False
            continue
        direct_path = direct_dir / direct_rel
        e2e_path = e2e_dir / e2e_rel
        if key.startswith("output_"):
            if not compare_csv(direct_path, e2e_path, comp_name):
                ok = False
        elif key.startswith("report_"):
            if not compare_report(direct_path, e2e_path, comp_name):
                ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(
        description="Compare direct and E2E privacy component results"
    )
    parser.add_argument("--direct", default="e2e/privacy/results/direct")
    parser.add_argument("--e2e", default="e2e/privacy/results/e2e")
    args = parser.parse_args()

    direct_dir = Path(args.direct)
    e2e_dir = Path(args.e2e)

    if not direct_dir.exists() or not e2e_dir.exists():
        print("Both --direct and --e2e directories must exist")
        sys.exit(1)

    with open(direct_dir / "index.json") as f:
        direct_index = json.load(f)

    ok = True
    for comp_key in direct_index:
        print(f"Comparing {comp_key} ...")
        if not compare_component(direct_dir, e2e_dir, comp_key):
            ok = False

    if ok:
        print("\nAll direct and E2E results match.")
    else:
        print("\nSome direct and E2E results differ.")
        sys.exit(1)


if __name__ == "__main__":
    main()
