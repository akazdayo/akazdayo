import json
import os
import pathlib
import subprocess
import sys
import tempfile

fixture_dir = pathlib.Path(os.environ["FIXTURE_DIR"])
repos_fixture = json.loads((fixture_dir / "repos.json").read_text(encoding="utf-8"))
commits_fixture = json.loads((fixture_dir / "commits.json").read_text(encoding="utf-8"))
fallback_pushed_at = repos_fixture[0]["pushed_at"]
bot_pushed_at = commits_fixture[0]["commit"]["committer"]["date"]
human_pushed_at = commits_fixture[1]["commit"]["committer"]["date"]
expected_text = os.environ["EXPECTED_TEXT"]
expected_state = os.environ["EXPECTED_STATE"]

if not (bot_pushed_at > human_pushed_at and fallback_pushed_at > human_pushed_at):
    raise SystemExit("self-idempotence fixture must keep automation timestamps newer than the human commit")
if expected_state == "[]":
    raise SystemExit("self-idempotence fixture unexpectedly normalized to an empty list")

with tempfile.TemporaryDirectory() as temp_dir:
    output_path = pathlib.Path(temp_dir) / "repos.nix"
    subprocess.run(
        [
            sys.executable,
            os.environ["SYNC_SCRIPT"],
            "--fixture-dir",
            str(fixture_dir),
            "--owner",
            "akazdayo",
            "--output",
            str(output_path),
        ],
        check=True,
    )
    actual_text = output_path.read_text(encoding="utf-8")

if actual_text != expected_text:
    raise SystemExit("self-idempotence output drifted from the validated expected repos.nix")
if f'pushedAt = "{human_pushed_at}";' not in actual_text:
    raise SystemExit("self repo did not stabilize on the latest human commit timestamp")
if f'pushedAt = "{bot_pushed_at}";' in actual_text:
    raise SystemExit("automation commit still controls self repo pushedAt")
