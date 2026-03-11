import importlib.util
import json
import os
import pathlib
from urllib.parse import parse_qs, urlparse

module_path = pathlib.Path(os.environ["SYNC_SCRIPT"])
spec = importlib.util.spec_from_file_location("sync_profile", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

page_map = {
    1: json.loads(pathlib.Path(os.environ["PAGE1"]).read_text(encoding="utf-8")),
    2: json.loads(pathlib.Path(os.environ["PAGE2"]).read_text(encoding="utf-8")),
}


def materialize():
    calls = []

    def fake_get_json(url, headers):
        del headers
        query = parse_qs(urlparse(url).query)
        page = int(query.get("page", ["1"])[0])
        calls.append(page)
        return page_map.get(page, [])

    module._get_json = fake_get_json
    raw_repos = module.fetch_all_repos("akazdayo", None)
    owned_public = [repo for repo in raw_repos if not repo.get("private", False)]
    repos = module.sort_repos([module.normalize_repo(repo) for repo in owned_public])
    module.validate_repos(repos)
    return calls, repos, module.repos_to_nix(repos)


first_calls, first_repos, first_text = materialize()
second_calls, second_repos, second_text = materialize()
expected_names = ["page2-alpha", "page2-beta"] + [
    f"page1-{index:03d}" for index in range(100)
]
actual_names = [repo["name"] for repo in first_repos]

if first_calls != [1, 2] or second_calls != [1, 2]:
    raise SystemExit(
        f"unexpected pagination traversal: {first_calls!r} / {second_calls!r}"
    )
if first_text != second_text or first_repos != second_repos:
    raise SystemExit(
        "pagination fixture did not merge deterministically across repeated runs"
    )
if actual_names != expected_names:
    raise SystemExit(
        "pagination fixture did not produce the expected merged and sorted order"
    )
if len(first_repos) != 102:
    raise SystemExit(
        f"expected 102 public repos after merging pages, got {len(first_repos)}"
    )
if any(repo["name"] == "page2-private" for repo in first_repos):
    raise SystemExit("private repos leaked into the normalized pagination output")
