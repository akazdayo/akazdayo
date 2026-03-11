#!/usr/bin/env python3
"""
sync-profile.py — fetch public owned repos from GitHub REST API and emit repos.nix.

Usage:
  # Live mode (requires GITHUB_TOKEN env var):
  python3 scripts/sync-profile.py --owner akazdayo --output repos.nix

  # Fixture mode — load data from a directory (no network):
  python3 scripts/sync-profile.py \
      --fixture-dir path/to/fixtures \
      --owner akazdayo \
      --output repos.nix

  # Fixture directory convention:
  #   <dir>/repos.json    — list of GitHub REST repo objects
  #   <dir>/commits.json  — list of GitHub REST commit objects (for self-repo)

  # Print to stdout without writing to disk:
  python3 scripts/sync-profile.py --owner akazdayo --stdout

  # Combine: fixture mode + stdout:
  python3 scripts/sync-profile.py \
      --fixture-dir path/to/fixtures \
      --owner akazdayo \
      --stdout

  # Legacy per-file fixture flags (still accepted):
  python3 scripts/sync-profile.py \
      --fixture-repos path/to/repos.json \
      --fixture-commits path/to/commits.json \
      --owner akazdayo \
      --dry-run

Environment:
  GITHUB_TOKEN  Personal access token (required in live mode).

Exit codes:
  0  Success — repos.nix written (or printed with --stdout / --dry-run).
  1  Validation or I/O error — repos.nix is never partially overwritten.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

GITHUB_API = "https://api.github.com"
API_VERSION = "2022-11-28"

# The exact field order mandated by nix/profile/schema.nix
FIELD_ORDER: list[str] = [
    "name",
    "url",
    "stars",
    "language",
    "pushedAt",
    "topics",
    "archived",
    "fork",
]

# Commits from the automation bot that are excluded when deriving pushedAt for
# the self-repo.  Extend this list if additional bot identifiers are added.
AUTOMATION_COMMIT_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\[bot\]", re.IGNORECASE),
    re.compile(r"github-actions", re.IGNORECASE),
    re.compile(r"dependabot", re.IGNORECASE),
    re.compile(r"sync[- ]profile", re.IGNORECASE),
    re.compile(r"auto[- ]?commit", re.IGNORECASE),
    re.compile(r"update repos\.nix", re.IGNORECASE),
]

PUSHED_AT_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
)

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def _build_headers(token: str | None) -> dict[str, str]:
    headers: dict[str, str] = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _get_json(url: str, headers: dict[str, str]) -> Any:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(
            f"GitHub API returned HTTP {exc.code} for {url}: {body}"
        ) from exc


# ---------------------------------------------------------------------------
# Pagination
# ---------------------------------------------------------------------------


def fetch_all_repos(owner: str, token: str | None) -> list[dict[str, Any]]:
    """Fetch every public owned repo via paginated REST calls."""
    headers = _build_headers(token)
    repos: list[dict[str, Any]] = []
    page = 1
    while True:
        url = (
            f"{GITHUB_API}/users/{owner}/repos"
            f"?type=owner&per_page=100&page={page}"
        )
        page_data: list[dict[str, Any]] = _get_json(url, headers)
        if not isinstance(page_data, list):
            raise RuntimeError(f"Unexpected response shape on page {page}: {page_data!r}")
        if not page_data:
            break
        repos.extend(page_data)
        if len(page_data) < 100:
            # Last page — no need to request further
            break
        page += 1
    return repos


def fetch_commits_for_repo(
    owner: str, repo_name: str, token: str | None, per_page: int = 100
) -> list[dict[str, Any]]:
    """Fetch up to *per_page* most-recent commits for a repository."""
    headers = _build_headers(token)
    url = (
        f"{GITHUB_API}/repos/{owner}/{repo_name}/commits"
        f"?per_page={per_page}&page=1"
    )
    data = _get_json(url, headers)
    if not isinstance(data, list):
        raise RuntimeError(
            f"Unexpected response shape from commits endpoint: {data!r}"
        )
    return data


# ---------------------------------------------------------------------------
# Self-repo stabilization
# ---------------------------------------------------------------------------

def _is_automation_commit(commit: dict[str, Any]) -> bool:
    """Return True if the commit looks like it was made by automation."""
    # Check committer login
    committer = (commit.get("committer") or {})
    committer_login: str = committer.get("login", "") or ""
    author = (commit.get("author") or {})
    author_login: str = author.get("login", "") or ""

    for login in (committer_login, author_login):
        for pattern in AUTOMATION_COMMIT_PATTERNS:
            if pattern.search(login):
                return True

    # Check git-level author/committer name and email inside commit.commit
    git_commit = commit.get("commit") or {}
    git_author = git_commit.get("author") or {}
    git_committer = git_commit.get("committer") or {}

    for field in (
        git_author.get("name", ""),
        git_author.get("email", ""),
        git_committer.get("name", ""),
        git_committer.get("email", ""),
    ):
        for pattern in AUTOMATION_COMMIT_PATTERNS:
            if pattern.search(field or ""):
                return True

    # Check commit message
    message: str = git_commit.get("message", "") or ""
    for pattern in AUTOMATION_COMMIT_PATTERNS:
        if pattern.search(message):
            return True

    return False


def derive_self_pushed_at(
    commits: list[dict[str, Any]],
    fallback_pushed_at: str,
) -> str:
    """
    Return the ISO 8601 UTC timestamp of the latest non-automation commit.
    Falls back to *fallback_pushed_at* if every recent commit is automation.
    """
    for commit in commits:
        if _is_automation_commit(commit):
            continue
        git_commit = commit.get("commit") or {}
        git_committer = git_commit.get("committer") or {}
        date_str: str | None = git_committer.get("date")
        if date_str and PUSHED_AT_RE.match(date_str):
            return date_str
        # Try author date as backup
        git_author = git_commit.get("author") or {}
        author_date: str | None = git_author.get("date")
        if author_date and PUSHED_AT_RE.match(author_date):
            return author_date
    return fallback_pushed_at


# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

def _normalize_pushed_at(raw: str | None) -> str:
    """
    Accept ISO 8601 strings in various forms and normalize to
    `YYYY-MM-DDTHH:MM:SSZ` (UTC, no fractional seconds).
    """
    if not raw:
        raise ValueError(f"pushedAt is missing or empty: {raw!r}")
    # Already canonical
    if PUSHED_AT_RE.match(raw):
        return raw
    # Try parsing with fractions or offset
    for fmt in (
        "%Y-%m-%dT%H:%M:%S.%fZ",
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S.%f%z",
    ):
        try:
            dt = datetime.strptime(raw, fmt)
            if dt.tzinfo is not None:
                dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
            return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            continue
    raise ValueError(f"Cannot parse pushedAt value: {raw!r}")


def normalize_repo(raw: dict[str, Any]) -> dict[str, Any]:
    """Normalize a raw GitHub REST repo object into the schema-required shape."""
    name: str = raw["name"]
    url: str = raw.get("html_url") or f"https://github.com/{raw.get('full_name', name)}"
    stars: int = int(raw.get("stargazers_count") or 0)
    language: str | None = raw.get("language") or None
    pushed_at_raw: str | None = raw.get("pushed_at")
    pushed_at = _normalize_pushed_at(pushed_at_raw)
    topics: list[str] = sorted(raw.get("topics") or [])
    archived: bool = bool(raw.get("archived", False))
    fork: bool = bool(raw.get("fork", False))

    return {
        "name": name,
        "url": url,
        "stars": stars,
        "language": language,
        "pushedAt": pushed_at,
        "topics": topics,
        "archived": archived,
        "fork": fork,
    }


def sort_repos(repos: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Sort repos by stars desc, then name asc — matches schema.nix repoLessThan."""
    return sorted(repos, key=lambda r: (-r["stars"], r["name"]))


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def _validate_repo(repo: dict[str, Any]) -> None:
    """Raise ValueError if *repo* does not satisfy the schema contract."""
    keys = sorted(repo.keys())
    expected = sorted(FIELD_ORDER)
    if keys != expected:
        raise ValueError(
            f"Repo {repo.get('name', '?')!r} has wrong fields: {keys} != {expected}"
        )
    name = repo["name"]
    if not isinstance(repo["name"], str):
        raise ValueError(f"{name}: `name` must be str")
    if not isinstance(repo["url"], str):
        raise ValueError(f"{name}: `url` must be str")
    if not isinstance(repo["stars"], int) or repo["stars"] < 0:
        raise ValueError(f"{name}: `stars` must be non-negative int")
    if repo["language"] is not None and not isinstance(repo["language"], str):
        raise ValueError(f"{name}: `language` must be null or str")
    if not isinstance(repo["pushedAt"], str) or not PUSHED_AT_RE.match(repo["pushedAt"]):
        raise ValueError(f"{name}: `pushedAt` must be ISO 8601 UTC")
    if not isinstance(repo["topics"], list) or not all(
        isinstance(t, str) for t in repo["topics"]
    ):
        raise ValueError(f"{name}: `topics` must be list of str")
    if repo["topics"] != sorted(repo["topics"]):
        raise ValueError(f"{name}: `topics` must be sorted ascending")
    if not isinstance(repo["archived"], bool):
        raise ValueError(f"{name}: `archived` must be bool")
    if not isinstance(repo["fork"], bool):
        raise ValueError(f"{name}: `fork` must be bool")


def validate_repos(repos: list[dict[str, Any]]) -> None:
    """Raise ValueError if the full repo list fails any schema check."""
    if not isinstance(repos, list):
        raise ValueError("`repos` must be a list")
    for repo in repos:
        _validate_repo(repo)
    sorted_repos = sort_repos(repos)
    if repos != sorted_repos:
        raise ValueError(
            "repos are not sorted by stars desc then name asc"
        )


# ---------------------------------------------------------------------------
# Nix serialization
# ---------------------------------------------------------------------------

def _nix_string(value: str) -> str:
    """Serialize a Python string to a Nix string literal."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("${", "\\${")
    return f'"{escaped}"'


def _nix_bool(value: bool) -> str:
    return "true" if value else "false"


def _nix_topics(topics: list[str]) -> str:
    if not topics:
        return "[ ]"
    inner = " ".join(_nix_string(t) for t in topics)
    return f"[ {inner} ]"


def _nix_null_or_string(value: str | None) -> str:
    return "null" if value is None else _nix_string(value)


def repo_to_nix(repo: dict[str, Any]) -> str:
    """Serialize a single normalized repo attrset in FIELD_ORDER."""
    lines = [
    "  {",
    f"    name = {_nix_string(repo['name'])};",
    f"    url = {_nix_string(repo['url'])};",
    f"    stars = {repo['stars']};",
    f"    language = {_nix_null_or_string(repo['language'])};",
    f"    pushedAt = {_nix_string(repo['pushedAt'])};",
    f"    topics = {_nix_topics(repo['topics'])};",
    f"    archived = {_nix_bool(repo['archived'])};",
    f"    fork = {_nix_bool(repo['fork'])};",
    "  }",
    ]
    return "\n".join(lines)


def repos_to_nix(repos: list[dict[str, Any]]) -> str:
    """Serialize a sorted, validated list of repos to a repos.nix string."""
    if not repos:
        return "[ ]\n"
    entries = "\n".join(repo_to_nix(r) for r in repos)
    return f"[\n{entries}\n]\n"


# ---------------------------------------------------------------------------
# Fixture loading
# ---------------------------------------------------------------------------

def load_fixture_repos(path: str) -> list[dict[str, Any]]:
    """Load a repos fixture JSON (list of GitHub REST repo objects)."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError(f"Fixture repos at {path!r} must be a JSON array")
    return data


def load_fixture_commits(path: str) -> list[dict[str, Any]]:
    """Load a commits fixture JSON (list of GitHub REST commit objects)."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError(f"Fixture commits at {path!r} must be a JSON array")
    return data


# ---------------------------------------------------------------------------
# Atomic write
# ---------------------------------------------------------------------------

def atomic_write(dest: str, content: str) -> None:
    """Write *content* to *dest* atomically via a sibling temp file + rename."""
    dest_dir = os.path.dirname(os.path.abspath(dest))
    fd, tmp_path = tempfile.mkstemp(dir=dest_dir, prefix=".repos.nix.tmp.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp_path, dest)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# Main orchestration
# ---------------------------------------------------------------------------

def run(
    owner: str,
    output: str | None,
    stdout: bool,
    fixture_dir: str | None,
    fixture_repos_path: str | None,
    fixture_commits_path: str | None,
    token: str | None,
) -> None:
    self_repo_name = owner  # akazdayo/akazdayo → repo name matches owner

    # Resolve fixture file paths: --fixture-dir takes precedence over the
    # legacy per-file flags, using the fixed convention repos.json / commits.json.
    resolved_repos_path = fixture_repos_path
    resolved_commits_path = fixture_commits_path
    if fixture_dir is not None:
        resolved_repos_path = os.path.join(fixture_dir, "repos.json")
        resolved_commits_path = os.path.join(fixture_dir, "commits.json")

    # 1. Obtain raw repo list
    if resolved_repos_path is not None:
        print(f"[sync-profile] fixture mode: loading repos from {resolved_repos_path}", file=sys.stderr)
        raw_repos = load_fixture_repos(resolved_repos_path)
    else:
        if not token:
            raise RuntimeError(
                "GITHUB_TOKEN is not set; export it or pass --token, "
                "or use --fixture-dir / --fixture-repos for offline mode."
            )
        print(f"[sync-profile] fetching repos for owner {owner!r} …", file=sys.stderr)
        raw_repos = fetch_all_repos(owner, token)

    # Keep only public, non-private repos that are owned (not forks from other users
    # are already captured by type=owner; archived are kept per schema contract).
    # The REST type=owner already excludes forked repos from the listing but the
    # fixture data may include them; we filter to owner repos only.
    owned_public = [
        r for r in raw_repos
        if not r.get("private", False)
    ]
    print(
        f"[sync-profile] {len(owned_public)} public owned repos found",
        file=sys.stderr,
    )

    # 2. Normalize each repo
    normalized: list[dict[str, Any]] = []
    for raw in owned_public:
        repo = normalize_repo(raw)

        # Self-repo stabilization: derive pushedAt from non-automation commits
        if raw.get("name") == self_repo_name or raw.get("full_name") == f"{owner}/{owner}":
            if resolved_commits_path is not None and os.path.exists(resolved_commits_path):
                print(
                    f"[sync-profile] fixture mode: loading commits from {resolved_commits_path}",
                    file=sys.stderr,
                )
                commits = load_fixture_commits(resolved_commits_path)
            elif resolved_commits_path is not None:
                print(
                    f"[sync-profile] commits fixture not found at {resolved_commits_path}, skipping stabilization",
                    file=sys.stderr,
                )
                commits = []
            else:
                print(
                    f"[sync-profile] fetching commits for self-repo {owner}/{owner} …",
                    file=sys.stderr,
                )
                commits = fetch_commits_for_repo(owner, self_repo_name, token)
            repo["pushedAt"] = derive_self_pushed_at(
                commits, fallback_pushed_at=repo["pushedAt"]
            )

        normalized.append(repo)

    # 3. Sort
    repos = sort_repos(normalized)

    # 4. Validate
    try:
        validate_repos(repos)
    except ValueError as exc:
        raise SystemExit(f"[sync-profile] VALIDATION ERROR: {exc}") from exc

    # 5. Serialize
    nix_content = repos_to_nix(repos)

    # 6. Emit
    if stdout or output is None:
        sys.stdout.write(nix_content)
    else:
        atomic_write(output, nix_content)
        print(f"[sync-profile] wrote {len(repos)} repos → {output}", file=sys.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch GitHub repos and emit repos.nix snapshot.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--owner",
        default=os.environ.get("GITHUB_REPOSITORY_OWNER", "akazdayo"),
        help="GitHub username whose repos to fetch (default: akazdayo).",
    )
    parser.add_argument(
        "--output",
        default="repos.nix",
        help="Path to write repos.nix (default: repos.nix).",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print repos.nix to stdout instead of writing to disk.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Alias for --stdout (kept for backward compatibility).",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub PAT (default: $GITHUB_TOKEN).",
    )
    parser.add_argument(
        "--fixture-dir",
        metavar="PATH",
        help=(
            "Load fixture data from a directory instead of hitting the API. "
            "Convention: <dir>/repos.json (repo list) and <dir>/commits.json "
            "(self-repo commit list)."
        ),
    )
    parser.add_argument(
        "--fixture-repos",
        metavar="PATH",
        help="Load repo list from a single JSON fixture file (legacy; --fixture-dir preferred).",
    )
    parser.add_argument(
        "--fixture-commits",
        metavar="PATH",
        help="Load commit list from a single JSON fixture file (legacy; --fixture-dir preferred).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    run(
        owner=args.owner,
        output=args.output,
        stdout=args.stdout or args.dry_run,
        fixture_dir=args.fixture_dir,
        fixture_repos_path=args.fixture_repos,
        fixture_commits_path=args.fixture_commits,
        token=args.token,
    )


if __name__ == "__main__":
    main()
