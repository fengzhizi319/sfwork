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

"""Drive the full frontend->backend->Kuscia->SecretFlow pipeline via SecretPad REST API.

The same parameter JSON files used by run_direct.py are replayed here. Outputs are
downloaded and saved to results/e2e so they can be compared with results/direct.

Usage:
    python e2e/privacy/run_e2e.py --param-dir e2e/privacy/params \
        --data-dir e2e/privacy/data --out e2e/privacy/results/e2e

Prerequisites:
- SecretPad backend reachable at http://127.0.0.1:8080
- Kuscia Docker environment (master + alice + bob) already running
- Custom SecretFlow image registered as the secretflow-image AppImage
"""

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import pandas as pd

# Cache for component output counts read from SecretPad component definitions.
_COMPONENT_OUTPUT_CACHE: Dict[str, int] = {}


def _component_output_count(comp: Dict[str, str]) -> int:
    """Return the number of outputs declared for a component in secretflow.json."""
    key = f"{comp['domain']}/{comp['name']}:{comp['version']}"
    if key in _COMPONENT_OUTPUT_CACHE:
        return _COMPONENT_OUTPUT_CACHE[key]
    # Search for the component definition used by the SecretPad backend.
    comp_def_path = Path(__file__).parent.parent.parent / "secretpad" / "config" / "components" / "secretflow.json"
    count = 1  # Fallback to a single output if the definition cannot be read.
    if comp_def_path.exists():
        try:
            with open(comp_def_path) as f:
                comp_list = json.load(f)
            for c in comp_list.get("comps", []):
                if c.get("domain") == comp["domain"] and c.get("name") == comp["name"] and c.get("version") == comp["version"]:
                    count = len(c.get("outputs", []))
                    break
        except Exception:
            pass
    _COMPONENT_OUTPUT_CACHE[key] = count
    return count


# Prefer requests if available; otherwise use urllib.
try:
    import requests

    HAS_REQUESTS = True
except Exception:  # pragma: no cover
    HAS_REQUESTS = False
    import urllib.error
    import urllib.request


class SecretPadClient:
    """Minimal typed client for the SecretPad backend API used in this test."""

    def __init__(self, base: str, user: str, password: str):
        self.base = base.rstrip("/")
        self.token = self._login(user, password)

    def _request(
        self,
        method: str,
        path: str,
        json_payload: Optional[Dict] = None,
        files: Optional[Dict] = None,
        extra_headers: Optional[Dict] = None,
        stream: bool = False,
    ) -> Dict[str, Any]:
        url = f"{self.base}{path}"
        headers = {}
        if path != "/api/login":
            headers["User-Token"] = self.token
        if extra_headers:
            headers.update(extra_headers)

        if HAS_REQUESTS:
            if files:
                resp = requests.request(
                    method, url, headers=headers, files=files, timeout=120
                )
            elif json_payload is not None:
                resp = requests.request(
                    method, url, headers=headers, json=json_payload, timeout=120
                )
            else:
                resp = requests.request(method, url, headers=headers, timeout=120)
            if stream:
                return {"_raw": resp}
            return resp.json()
        else:
            data = None
            if json_payload is not None:
                data = json.dumps(json_payload).encode("utf-8")
                headers["Content-Type"] = "application/json"
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            resp = urllib.request.urlopen(req, timeout=120)
            if stream:
                return {"_raw": resp}
            return json.loads(resp.read().decode("utf-8"))

    def _login(self, user: str, password: str) -> str:
        pwd_hash = hashlib.sha256(password.encode("utf-8")).hexdigest()
        resp = self._request(
            "POST",
            "/api/login",
            {"name": user, "passwordHash": pwd_hash},
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"Login failed: {resp}")
        return resp["data"]["token"]

    def create_project(self, name: str, description: str, compute_mode: str = "MPC") -> str:
        resp = self._request(
            "POST",
            "/api/v1alpha1/project/create",
            {
                "name": name,
                "description": description,
                "computeMode": compute_mode,
                "teeNodeId": "",
            },
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"create_project failed: {resp}")
        return resp["data"]["projectId"]

    def add_project_nodes(self, project_id: str, nodes: List[str]):
        for node in nodes:
            resp = self._request(
                "POST",
                "/api/v1alpha1/project/node/add",
                {"projectId": project_id, "nodeId": node},
            )
            if resp.get("status", {}).get("code") != 0:
                raise RuntimeError(f"add_project_node {node} failed: {resp}")

    def upload_data(self, node_id: str, csv_path: Path) -> str:
        """Upload CSV to the node and return the realName to use as relativeUri."""
        if HAS_REQUESTS:
            with open(csv_path, "rb") as f:
                resp = self._request(
                    "POST",
                    "/api/v1alpha1/data/upload",
                    files={
                        "file": f,
                        "Node-Id": (None, node_id),
                    },
                )
        else:
            # urllib multipart upload is verbose; require requests for upload.
            raise RuntimeError("upload_data requires the 'requests' library")
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"upload_data failed: {resp}")
        return resp["data"]["realName"]

    def create_datatable(
        self,
        owner_id: str,
        node_ids: List[str],
        datatable_name: str,
        relative_uri: str,
        description: str,
        columns: List[Dict],
    ) -> str:
        payload = {
            "ownerId": owner_id,
            "nodeIds": node_ids,
            "datatableName": datatable_name,
            "datasourceId": "default-data-source",
            "datasourceName": "default-data-source",
            "datasourceType": "LOCAL",
            "relativeUri": relative_uri,
            "desc": description,
            "columns": columns,
        }
        # SecretPad backend may throttle rapid datatable creation; retry a few times.
        for attempt in range(4):
            resp = self._request("POST", "/api/v1alpha1/datatable/create", payload)
            if resp.get("status", {}).get("code") == 0:
                return resp["data"]["dataTableNodeInfos"][0]["domainDataId"]
            if resp.get("status", {}).get("code") == 2020111012:
                time.sleep(5 + attempt * 5)
                continue
            raise RuntimeError(f"create_datatable failed: {resp}")
        raise RuntimeError(f"create_datatable failed after retries: {resp}")

    def add_datatable_to_project(
        self, project_id: str, node_id: str, datatable_id: str
    ):
        resp = self._request(
            "POST",
            "/api/v1alpha1/project/datatable/add",
            {
                "projectId": project_id,
                "nodeId": node_id,
                "datatableId": datatable_id,
            },
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"add_datatable_to_project failed: {resp}")

    def create_graph(self, project_id: str, name: str) -> str:
        resp = self._request(
            "POST",
            "/api/v1alpha1/graph/create",
            {"projectId": project_id, "name": name},
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"create_graph failed: {resp}")
        return resp["data"]["graphId"]

    def update_graph(
        self,
        project_id: str,
        graph_id: str,
        nodes: List[Dict],
        edges: List[Dict],
        data_source_config: List[Dict],
    ):
        resp = self._request(
            "POST",
            "/api/v1alpha1/graph/update",
            {
                "projectId": project_id,
                "graphId": graph_id,
                "nodes": nodes,
                "edges": edges,
                "dataSourceConfig": data_source_config,
            },
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"update_graph failed: {resp}")

    def start_graph(self, project_id: str, graph_id: str, node_ids: List[str]) -> str:
        resp = self._request(
            "POST",
            "/api/v1alpha1/graph/start",
            {
                "projectId": project_id,
                "graphId": graph_id,
                "nodes": node_ids,
            },
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"start_graph failed: {resp}")
        return resp["data"]["jobId"]

    def poll_status(
        self, project_id: str, graph_id: str, timeout: int = 300
    ) -> List[Dict]:
        deadline = time.time() + timeout
        while time.time() < deadline:
            resp = self._request(
                "POST",
                "/api/v1alpha1/graph/node/status",
                {"projectId": project_id, "graphId": graph_id},
            )
            if resp.get("status", {}).get("code") != 0:
                raise RuntimeError(f"list_graph_node_status failed: {resp}")
            nodes = resp["data"]["nodes"]
            if all(n["status"] == "SUCCEED" for n in nodes):
                return nodes
            if any(n["status"] == "FAILED" for n in nodes):
                raise RuntimeError(f"Graph node failed: {nodes}")
            time.sleep(5)
        raise RuntimeError("Timeout waiting for graph to finish")

    def get_node_output(
        self,
        project_id: str,
        graph_id: str,
        graph_node_id: str,
        output_id: str,
    ) -> Dict:
        resp = self._request(
            "POST",
            "/api/v1alpha1/graph/node/output",
            {
                "projectId": project_id,
                "graphId": graph_id,
                "graphNodeId": graph_node_id,
                "outputId": output_id,
            },
        )
        if resp.get("status", {}).get("code") != 0:
            raise RuntimeError(f"get_node_output failed: {resp}")
        return resp["data"]

    def download_data(self, node_id: str, domain_data_id: str, save_path: Path):
        raw = self._request(
            "POST",
            "/api/v1alpha1/data/download",
            {"nodeId": node_id, "domainDataId": domain_data_id},
            stream=True,
        )
        if HAS_REQUESTS:
            resp = raw["_raw"]
            resp.raise_for_status()
            with open(save_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
        else:
            raise RuntimeError("download_data requires the 'requests' library")


def _value_to_attr(value: Any) -> Dict:
    """Convert a Python value to the Attribute one-of JSON used by SecretPad."""
    if isinstance(value, bool):
        return {"b": value, "is_na": False}
    if isinstance(value, int):
        return {"i64": value, "is_na": False}
    if isinstance(value, float):
        return {"f": value, "is_na": False}
    if isinstance(value, str):
        return {"s": value, "is_na": False}
    if isinstance(value, list):
        if not value:
            return {"is_na": False}
        first = value[0]
        if isinstance(first, bool):
            return {"bs": value, "is_na": False}
        if isinstance(first, int):
            return {"i64s": value, "is_na": False}
        if isinstance(first, float):
            return {"fs": value, "is_na": False}
        if isinstance(first, str):
            return {"ss": value, "is_na": False}
    raise ValueError(f"Unsupported attribute value type: {type(value)} for {value}")


def _build_attr_paths(attrs: Dict[str, Any]) -> tuple[List[str], List[Dict]]:
    attr_paths = sorted(attrs.keys())
    attr_values = [_value_to_attr(attrs[p]) for p in attr_paths]
    return attr_paths, attr_values


def _dtype_to_col_type(dtype: str) -> str:
    if dtype.startswith("int"):
        return "int"
    if dtype.startswith("float"):
        return "float"
    return "str"


def _build_graph_nodes(
    graph_id: str, param: Dict, datatable_id: str, has_input: bool
) -> List[Dict]:
    nodes = []
    if has_input:
        nodes.append(
            {
                "codeName": "read_data/datatable",
                "graphNodeId": f"{graph_id}-node-1",
                "label": "read_data",
                "x": 100,
                "y": 100,
                "inputs": [],
                "outputs": [f"{graph_id}-node-1-output-0"],
                "nodeDef": {
                    "domain": "read_data",
                    "name": "datatable",
                    "version": "0.0.1",
                    "attrPaths": ["datatable_selected"],
                    "attrs": [{"s": datatable_id, "is_na": False}],
                },
            }
        )
        comp_node_id = f"{graph_id}-node-2"
        comp_input = [f"{graph_id}-node-1-output-0"]
        comp_output_idx = 0
    else:
        comp_node_id = f"{graph_id}-node-1"
        comp_input = []
        comp_output_idx = -1

    comp = param["component"]
    attr_paths, attr_values = _build_attr_paths(param["attrs"])
    comp_outputs = [
        f"{comp_node_id}-output-{i}"
        for i in range(_component_output_count(comp))
    ]
    nodes.append(
        {
            "codeName": f"{comp['domain']}/{comp['name']}",
            "graphNodeId": comp_node_id,
            "label": comp["name"],
            "x": 300,
            "y": 100,
            "inputs": comp_input,
            "outputs": comp_outputs,
            "nodeDef": {
                "domain": comp["domain"],
                "name": comp["name"],
                "version": comp["version"],
                "attrPaths": attr_paths,
                "attrs": attr_values,
            },
        }
    )
    return nodes


def _build_graph_edges(graph_id: str, has_input: bool) -> List[Dict]:
    if not has_input:
        return []
    return [
        {
            "edgeId": f"{graph_id}-node-1-output-0__{graph_id}-node-2-input-0",
            "source": f"{graph_id}-node-1",
            "sourceAnchor": f"{graph_id}-node-1-output-0",
            "target": f"{graph_id}-node-2",
            "targetAnchor": f"{graph_id}-node-2-input-0",
        }
    ]


def run_e2e_component(
    client: SecretPadClient,
    param: Dict,
    data_dir: Path,
    out_dir: Path,
    node_id: str = "alice",
) -> Dict:
    comp = param["component"]
    comp_name = comp["name"]
    has_input = param.get("input_data") is not None

    import datetime

    ts = datetime.datetime.now().strftime("%m%d%H%M%S")
    short = comp_name.replace("differential_privacy", "dp").replace("local_", "l").replace("_", "")
    project_name = f"{short[:10]}-e2e-{ts}"
    project_id = client.create_project(project_name, f"E2E for {comp_name}")
    client.add_project_nodes(project_id, ["alice", "bob"])
    time.sleep(2)

    datatable_id = None
    if has_input:
        data_file = param["input_data"]
        csv_path = data_dir / data_file
        df = pd.read_csv(csv_path)
        real_name = client.upload_data(node_id, csv_path)
        time.sleep(1)
        columns = [
            {
                "colName": col,
                "colType": _dtype_to_col_type(str(t)),
                "colComment": "",
            }
            for col, t in zip(df.columns, df.dtypes)
        ]
        datatable_id = client.create_datatable(
            owner_id=node_id,
            node_ids=[node_id],
            datatable_name=f"{comp_name}_input",
            relative_uri=real_name,
            description=f"Input for {comp_name}",
            columns=columns,
        )
        client.add_datatable_to_project(project_id, node_id, datatable_id)

    graph_id = client.create_graph(project_id, f"{comp_name}-graph")
    nodes = _build_graph_nodes(graph_id, param, datatable_id, has_input)
    edges = _build_graph_edges(graph_id, has_input)
    data_source_config = [{"nodeId": node_id, "dataSourceId": "default-data-source"}]
    client.update_graph(project_id, graph_id, nodes, edges, data_source_config)

    comp_node_id = nodes[-1]["graphNodeId"]
    node_ids_to_start = [n["graphNodeId"] for n in nodes]
    client.start_graph(project_id, graph_id, node_ids_to_start)
    client.poll_status(project_id, graph_id)

    comp_out = out_dir / comp_name
    comp_out.mkdir(parents=True, exist_ok=True)
    saved = {"component": comp, "attrs": param["attrs"]}

    for i, output_id in enumerate(nodes[-1]["outputs"]):
        output = client.get_node_output(project_id, graph_id, comp_node_id, output_id)
        meta = output.get("meta", {})
        if output.get("type") == "table":
            rows = meta.get("rows", [])
            if rows:
                table_id = rows[0]["tableId"]
                csv_path = comp_out / f"output_{i}.csv"
                client.download_data(node_id, table_id, csv_path)
                saved[f"output_{i}"] = str(csv_path.relative_to(out_dir))
        elif output.get("type") == "report":
            report_path = comp_out / f"report_{i}.json"
            tabs = output.get("tabs")
            with open(report_path, "w") as f:
                json.dump({"tabs": tabs}, f, ensure_ascii=False, indent=2)
            saved[f"report_{i}"] = str(report_path.relative_to(out_dir))

    with open(comp_out / "summary.json", "w") as f:
        json.dump(saved, f, ensure_ascii=False, indent=2)

    return saved


def main():
    parser = argparse.ArgumentParser(
        description="Run privacy component E2E through SecretPad API"
    )
    parser.add_argument(
        "--base",
        default="http://127.0.0.1:8080",
        help="SecretPad backend base URL",
    )
    parser.add_argument(
        "--user",
        default="admin",
        help="Login user",
    )
    parser.add_argument(
        "--password",
        default="12345678",
        help="Login password",
    )
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
        default="e2e/privacy/results/e2e",
        help="Output directory for E2E results",
    )
    parser.add_argument(
        "--node",
        default="alice",
        help="Node that owns the input data",
    )
    args = parser.parse_args()

    if not HAS_REQUESTS:
        print("ERROR: the 'requests' library is required for the E2E driver.")
        sys.exit(1)

    param_dir = Path(args.param_dir)
    data_dir = Path(args.data_dir)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    client = SecretPadClient(args.base, args.user, args.password)
    print(f"Logged in as {args.user}")

    results = {}
    for param_file in sorted(param_dir.glob("*.json")):
        print(f"\nE2E: {param_file.stem}")
        with open(param_file) as f:
            param = json.load(f)
        saved = run_e2e_component(client, param, data_dir, out_dir, args.node)
        results[param_file.stem] = saved
        print(f"  -> saved to {out_dir / param['component']['name']}")
        time.sleep(2)

    with open(out_dir / "index.json", "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\nAll E2E results written to {out_dir}")


if __name__ == "__main__":
    main()
