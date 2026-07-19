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

"""Regenerate SecretPad component configs from the local SecretFlow source tree.

This is the local-dev counterpart of secretpad/scripts/update-sf-components.sh,
which pulls component definitions from a Docker image. When running SecretPad
backend directly against the source tree, use this script to keep
secretpad/config/components/secretflow.json and config/i18n/secretflow.json in
sync with the current SecretFlow code.

Usage:
    cd /path/to/sfwork
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate sf310
    python scripts/update-sf-components-local.py
"""

import json
import sys
from pathlib import Path

# Allow the script to be run from the workspace root while importing the local
# secretflow source tree instead of an installed package.
_PROJECT_ROOT = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(_PROJECT_ROOT / "secretflow"))

from google.protobuf.json_format import MessageToJson

from secretflow.component.core import get_comp_list_def
from secretflow.component.core.i18n import get_translation


def _project_root() -> Path:
    return _PROJECT_ROOT


def _dump_translation(translation: dict) -> str:
    return json.dumps(translation, ensure_ascii=False, indent=2)


def main():
    root = _project_root()

    comp_list = get_comp_list_def()
    comp_list_json = MessageToJson(
        comp_list,
        including_default_value_fields=False,
        indent=2,
    )
    translation = get_translation()
    translation_json = _dump_translation(translation)

    targets = [
        root / "secretpad" / "config" / "components" / "secretflow.json",
        root / "secretpad" / "secretpad-service" / "src" / "test" / "resources" / "config" / "components" / "secretflow.json",
    ]
    i18n_targets = [
        root / "secretpad" / "config" / "i18n" / "secretflow.json",
        root / "secretpad" / "secretpad-service" / "src" / "test" / "resources" / "config" / "i18n" / "secretflow.json",
    ]

    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(comp_list_json, encoding="utf-8")
        print(f"[components] wrote {target}")

    for target in i18n_targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(translation_json, encoding="utf-8")
        print(f"[i18n] wrote {target}")

    print(f"\nSynced {len(comp_list.comps)} components and {len(translation)} translation entries.")


if __name__ == "__main__":
    main()
