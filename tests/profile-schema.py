import os
import pathlib
import subprocess
import sys
import tempfile

committed_state = os.environ["COMMITTED_STATE"]
expected_text = os.environ["EXPECTED_TEXT"]
expected_state = os.environ["EXPECTED_STATE"]
invalid_partial_fixture_dir = pathlib.Path(os.environ["INVALID_PARTIAL_DIR"])
if committed_state not in {"absent", "present"}:
    raise SystemExit(f"unexpected committed repo state: {committed_state}")
if expected_state == "[]":
    raise SystemExit("schema fixture unexpectedly normalized to an empty list")

with tempfile.TemporaryDirectory() as temp_dir:
    output_path = pathlib.Path(temp_dir) / "repos.nix"
    subprocess.run(
        [
            sys.executable,
            os.environ["SYNC_SCRIPT"],
            "--fixture-dir",
            os.environ["SCHEMA_FIXTURE_DIR"],
            "--owner",
            "akazdayo",
            "--output",
            str(output_path),
        ],
        check=True,
    )
    actual_text = output_path.read_text(encoding="utf-8")

if actual_text != expected_text:
    raise SystemExit("schema fixture output drifted from the validated expected repos.nix")

for needle in (
    'language = null;',
    'name = "escape-\\${value}";',
    'topics = [ "back\\\\slash" "quote\\"topic" "topic\\${value}" ];',
):
    if needle not in actual_text:
        raise SystemExit(f"missing expected serialized fragment: {needle}")

with tempfile.TemporaryDirectory() as temp_dir:
    output_path = pathlib.Path(temp_dir) / "repos.nix"
    result = subprocess.run(
        [
            sys.executable,
            os.environ["SYNC_SCRIPT"],
            "--fixture-dir",
            str(invalid_partial_fixture_dir),
            "--owner",
            "akazdayo",
            "--output",
            str(output_path),
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0:
        raise SystemExit("invalid/partial fixture unexpectedly succeeded")
    if output_path.exists():
        raise SystemExit("invalid/partial fixture wrote repos.nix despite failing")

if "pushedAt is missing or empty" not in result.stderr:
    raise SystemExit(
        f"invalid/partial fixture failed for an unexpected reason: {result.stderr!r}"
    )
