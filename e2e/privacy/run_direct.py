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

"""Directly run a privacy component in simulation mode using saved params.

This script produces the "expected" outputs that the E2E backend driver will
compare against. All randomness is seeded, so repeated runs are deterministic.

Usage:
    source $(conda info --base)/etc/profile.d/conda.sh && conda activate sf310
    python e2e/privacy/run_direct.py --param e2e/privacy/params/k_anonymity.json \
        --out e2e/privacy/results/direct
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

import pandas as pd
from secretflow_spec.v1.data_pb2 import (
    DistData,
    IndividualTable,
    StorageConfig,
    TableSchema,
)
from secretflow_spec.v1.report_pb2 import Report

from secretflow.component.core import (
    BufferedIO,
    DistDataType,
    build_node_eval_param,
    comp_eval,
    make_storage,
)


def dtype_to_feature_type(dtype: str) -> str:
    """Map pandas dtype name to SecretFlow TableSchema feature type."""
    if dtype.startswith("int"):
        return "int64"
    if dtype.startswith("float"):
        return "float64"
    return "str"


def load_param(param_path: str) -> dict:
    with open(param_path) as f:
        return json.load(f)


def run_component(param: dict, comp_key: str, data_dir: Path, out_dir: Path) -> dict:
    comp = param["component"]
    attrs = param.get("attrs", {})
    data_file = param.get("input_data")
    input_party = param.get("input_party", "alice")

    workdir = tempfile.mkdtemp(prefix="sf_privacy_e2e_direct_")
    storage_config = StorageConfig(
        type="local_fs", local_fs=StorageConfig.LocalFSConfig(wd=workdir)
    )
    storage = make_storage(storage_config)

    output_uris = []
    if comp["name"] in {
        "k_anonymity",
        "l_diversity",
        "sanitization",
        "data_classification",
        "local_differential_privacy",
    }:
        output_uris = ["output/table", "output/report"]
    elif comp["name"] == "differential_privacy":
        output_uris = ["output/report"]
    elif comp["name"] == "query_obfuscation":
        output_uris = ["output/report"]
    else:
        raise ValueError(f"Unsupported component: {comp['name']}")

    inputs = []
    if data_file:
        input_path = f"input/{data_file}"
        df = pd.read_csv(data_dir / data_file)
        with storage.get_writer(input_path) as w:
            df.to_csv(w, index=False)
        schema = TableSchema(
            features=list(df.columns),
            feature_types=[dtype_to_feature_type(str(t)) for t in df.dtypes],
        )
        table = IndividualTable(schema=schema)
        inputs = [
            DistData(
                name="input_data",
                type=str(DistDataType.INDIVIDUAL_TABLE),
                data_refs=[
                    DistData.DataRef(
                        uri=input_path, party=input_party, format="csv"
                    )
                ],
            )
        ]
        inputs[0].meta.Pack(table)

    node_param = build_node_eval_param(
        domain=comp["domain"],
        name=comp["name"],
        version=comp["version"],
        attrs=attrs,
        inputs=inputs,
        output_uris=output_uris,
    )

    result = comp_eval(
        param=node_param, storage_config=storage_config, cluster_config=None
    )

    comp_out = out_dir / comp_key
    comp_out.mkdir(parents=True, exist_ok=True)
    saved = {"component": comp, "attrs": attrs}

    for i, out in enumerate(result.outputs):
        if out.type == str(DistDataType.INDIVIDUAL_TABLE):
            bio = BufferedIO(storage.get_reader(out.data_refs[0].uri))
            try:
                import pyarrow.orc as orc

                out_df = orc.ORCFile(bio.native).read().to_pandas()
            finally:
                bio.close()
            csv_path = comp_out / f"output_{i}.csv"
            out_df.to_csv(csv_path, index=False)
            saved[f"output_{i}"] = str(csv_path.relative_to(out_dir))
        elif out.type == str(DistDataType.REPORT):
            from google.protobuf import json_format

            report = Report()
            out.meta.Unpack(report)
            report_path = comp_out / f"report_{i}.json"
            report_dict = json_format.MessageToDict(
                report, preserving_proto_field_name=True
            )
            with open(report_path, "w") as f:
                json.dump(report_dict, f, ensure_ascii=False, indent=2)
            saved[f"report_{i}"] = str(report_path.relative_to(out_dir))

    with open(comp_out / "summary.json", "w") as f:
        json.dump(saved, f, ensure_ascii=False, indent=2)

    return saved


def main():
    parser = argparse.ArgumentParser(description="Run privacy components directly")
    parser.add_argument(
        "--param-dir",
        default="e2e/privacy/params",
        help="Directory containing param JSON files",
    )
    parser.add_argument(
        "--data-dir",
        default="e2e/privacy/data",
        help="Directory containing input CSV files",
    )
    parser.add_argument(
        "--out",
        default="e2e/privacy/results/direct",
        help="Output directory for direct run results",
    )
    args = parser.parse_args()

    param_dir = Path(args.param_dir)
    data_dir = Path(args.data_dir)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    results = {}
    for param_file in sorted(param_dir.glob("*.json")):
        print(f"Running {param_file.stem} ...")
        param = load_param(str(param_file))
        saved = run_component(param, param_file.stem, data_dir, out_dir)
        results[param_file.stem] = saved
        print(f"  -> saved to {out_dir / param['component']['name']}")

    with open(out_dir / "index.json", "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\nAll direct results written to {out_dir}")


if __name__ == "__main__":
    main()
