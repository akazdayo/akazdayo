{
  description = "Minimal flake contracts for the GitHub profile README";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        let
          staticProfile = import ./nix/profile/static.nix;
          schema = import ./nix/profile/schema.nix;
          aggregate = import ./nix/profile/aggregate.nix {
            static = staticProfile;
            inherit schema;
          };

          readme = pkgs.writeTextFile {
            name = "readme";
            destination = "/README.md";
            text = import ./nix/profile/render-readme.nix { inherit aggregate; };
          };

          profileJson = pkgs.writeTextFile {
            name = "profile-json";
            destination = "/profile.json";
            text = import ./nix/profile/render-profile-json.nix { inherit aggregate; };
          };

          committedRepos =
            if builtins.pathExists ./repos.nix then schema.validateRepos (import ./repos.nix) else null;
          committedReposState = if committedRepos == null then "absent" else "present";

          schemaFixtureDir = ./tests/fixtures/github-rest/schema;
          schemaFixtureExpected = ./tests/fixtures/github-rest/schema/expected.nix;
          schemaFixtureExpectedText = builtins.readFile schemaFixtureExpected;
          schemaFixtureExpectedRepos = schema.validateRepos (import schemaFixtureExpected);
          schemaFixtureExpectedState = builtins.toJSON schemaFixtureExpectedRepos;

          selfIdempotenceFixtureDir = ./tests/fixtures/github-rest/self-idempotence;
          selfIdempotenceExpected = ./tests/fixtures/github-rest/self-idempotence/expected.nix;
          selfIdempotenceExpectedText = builtins.readFile selfIdempotenceExpected;
          selfIdempotenceExpectedRepos = schema.validateRepos (import selfIdempotenceExpected);
          selfIdempotenceExpectedState = builtins.toJSON selfIdempotenceExpectedRepos;

          invalidPartialFixtureDir = ./tests/fixtures/github-rest/invalid-partial;

          paginationPage1 = ./tests/fixtures/github-rest/pagination/page-1.json;
          paginationPage2 = ./tests/fixtures/github-rest/pagination/page-2.json;

          mkPythonCheck =
            name: script:
            let
              scriptFile = pkgs.writeText "${name}.py" script;
            in
            pkgs.runCommand name { nativeBuildInputs = [ pkgs.python3 ]; } ''
              ${pkgs.python3}/bin/python3 ${scriptFile}
              touch "$out"
            '';

          generateReadmeBin = pkgs.writeShellApplication {
            name = "generate-readme";
            text = ''
              ${pkgs.nix}/bin/nix build "path:$PWD#readme"
              ${pkgs.coreutils}/bin/install -m 0644 result/README.md README.md
            '';
          };

          syncProfileBin = pkgs.writeShellApplication {
            name = "sync-profile";
            text = ''
              ${pkgs.python3}/bin/python3 ${./scripts/sync-profile.py} "$@"
              ${pkgs.nix}/bin/nix build "path:$PWD#profile-json"
              exec ${pkgs.nix}/bin/nix run "path:$PWD#generate-readme"
            '';
          };
        in
        {
          packages = {
            readme = readme;
            default = readme;
            "profile-json" = profileJson;
          };

          apps = {
            "generate-readme" = {
              type = "app";
              program = "${generateReadmeBin}/bin/generate-readme";
              meta.description = "Emit the generated README artifact";
            };

            "sync-profile" = {
              type = "app";
              program = "${syncProfileBin}/bin/sync-profile";
              meta.description = "Emit the machine-readable profile artifact";
            };
          };

          checks = {
            "readme-parity" = pkgs.runCommand "readme-parity" { } ''
              cmp ${readme}/README.md ${./README.md}
              touch "$out"
            '';

            "profile-schema" = mkPythonCheck "profile-schema" ''
              import pathlib
              import subprocess
              import sys
              import tempfile

              committed_state = "${committedReposState}"
              expected_text = ${builtins.toJSON schemaFixtureExpectedText}
              expected_state = ${builtins.toJSON schemaFixtureExpectedState}
              invalid_partial_fixture_dir = pathlib.Path("${invalidPartialFixtureDir}")
              if committed_state not in {"absent", "present"}:
                  raise SystemExit(f"unexpected committed repo state: {committed_state}")
              if expected_state == "[]":
                  raise SystemExit("schema fixture unexpectedly normalized to an empty list")

              with tempfile.TemporaryDirectory() as temp_dir:
                  output_path = pathlib.Path(temp_dir) / "repos.nix"
                  subprocess.run(
                      [
                          sys.executable,
                          "${./scripts/sync-profile.py}",
                          "--fixture-dir",
                          "${schemaFixtureDir}",
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
                  'name = "escape-\\''${value}";',
                  'topics = [ "back\\\\slash" "quote\\"topic" "topic\\''${value}" ];',
              ):
                  if needle not in actual_text:
                      raise SystemExit(f"missing expected serialized fragment: {needle}")

              with tempfile.TemporaryDirectory() as temp_dir:
                  output_path = pathlib.Path(temp_dir) / "repos.nix"
                  result = subprocess.run(
                      [
                          sys.executable,
                          "${./scripts/sync-profile.py}",
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
            '';

            "self-idempotence" = mkPythonCheck "self-idempotence" ''
              import json
              import pathlib
              import subprocess
              import sys
              import tempfile

              fixture_dir = pathlib.Path("${selfIdempotenceFixtureDir}")
              repos_fixture = json.loads((fixture_dir / "repos.json").read_text(encoding="utf-8"))
              commits_fixture = json.loads((fixture_dir / "commits.json").read_text(encoding="utf-8"))
              fallback_pushed_at = repos_fixture[0]["pushed_at"]
              bot_pushed_at = commits_fixture[0]["commit"]["committer"]["date"]
              human_pushed_at = commits_fixture[1]["commit"]["committer"]["date"]
              expected_text = ${builtins.toJSON selfIdempotenceExpectedText}
              expected_state = ${builtins.toJSON selfIdempotenceExpectedState}

              if not (bot_pushed_at > human_pushed_at and fallback_pushed_at > human_pushed_at):
                  raise SystemExit("self-idempotence fixture must keep automation timestamps newer than the human commit")
              if expected_state == "[]":
                  raise SystemExit("self-idempotence fixture unexpectedly normalized to an empty list")

              with tempfile.TemporaryDirectory() as temp_dir:
                  output_path = pathlib.Path(temp_dir) / "repos.nix"
                  subprocess.run(
                      [
                          sys.executable,
                          "${./scripts/sync-profile.py}",
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
            '';

            "pagination-fixture" = mkPythonCheck "pagination-fixture" ''
              import importlib.util
              import json
              import pathlib
              from urllib.parse import parse_qs, urlparse

              module_path = pathlib.Path("${./scripts/sync-profile.py}")
              spec = importlib.util.spec_from_file_location("sync_profile", module_path)
              module = importlib.util.module_from_spec(spec)
              spec.loader.exec_module(module)

              page_map = {
                  1: json.loads(pathlib.Path("${paginationPage1}").read_text(encoding="utf-8")),
                  2: json.loads(pathlib.Path("${paginationPage2}").read_text(encoding="utf-8")),
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
              expected_names = ["page2-alpha", "page2-beta"] + [f"page1-{index:03d}" for index in range(100)]
              actual_names = [repo["name"] for repo in first_repos]

              if first_calls != [1, 2] or second_calls != [1, 2]:
                  raise SystemExit(f"unexpected pagination traversal: {first_calls!r} / {second_calls!r}")
              if first_text != second_text or first_repos != second_repos:
                  raise SystemExit("pagination fixture did not merge deterministically across repeated runs")
              if actual_names != expected_names:
                  raise SystemExit("pagination fixture did not produce the expected merged and sorted order")
              if len(first_repos) != 102:
                  raise SystemExit(f"expected 102 public repos after merging pages, got {len(first_repos)}")
              if any(repo["name"] == "page2-private" for repo in first_repos):
                  raise SystemExit("private repos leaked into the normalized pagination output")
            '';
            "workflow-smoke" = pkgs.runCommand "workflow-smoke" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              workflow=${./.github/workflows/sync-profile.yml}

              # Basic trigger and structure assertions
              grep -F 'workflow_dispatch:' "$workflow"
              grep -F 'schedule:' "$workflow"
              grep -F 'concurrency:' "$workflow"
              grep -F 'contents: write' "$workflow"
              grep -F "git commit -m 'chore(profile): refresh generated profile [skip ci]'" "$workflow"

              # Push path filter must not include generated output files
              python3 - "$workflow" <<'EOF'
              import sys, re

              text = open(sys.argv[1]).read()

              # Locate the push.paths block
              paths_match = re.search(r'push:\s*\n\s*paths:\s*\n((?:\s+- .+\n)+)', text)
              if not paths_match:
                  sys.exit("could not locate push.paths block in workflow")

              paths_block = paths_match.group(1)
              path_entries = [line.strip().lstrip('- ') for line in paths_block.strip().splitlines()]

              # Generated outputs must be excluded from the source-only push filter
              for forbidden in ('repos.nix', 'README.md'):
                  if any(forbidden == entry or entry == forbidden for entry in path_entries):
                      sys.exit(f"generated output '{forbidden}' must not appear in push path filter")

              # Permissions contract: refresh job must declare contents: read
              refresh_section = re.search(
                  r'(refresh:\s*\n(?:[ \t]+.*\n)*)',
                  text,
              )
              if not refresh_section:
                  sys.exit("could not locate refresh job block")
              refresh_block = refresh_section.group(1)
              if 'contents: read' not in refresh_block:
                  sys.exit("refresh job must declare 'contents: read' permission")

              # Permissions contract: contents: write must not appear outside commit-generated job
              # Split on job boundaries and check write only lives under commit-generated
              commit_section = re.search(
                  r'(commit-generated:\s*\n(?:[ \t]+.*\n)*)',
                  text,
              )
              if not commit_section:
                  sys.exit("could not locate commit-generated job block")
              commit_block = commit_section.group(1)
              if 'contents: write' not in commit_block:
                  sys.exit("commit-generated job must declare 'contents: write' permission")

              # contents: write must not appear in the refresh job block
              if 'contents: write' in refresh_block:
                  sys.exit("refresh job must not declare 'contents: write'")

              print("workflow-smoke: all policy assertions passed")
              EOF

              touch "$out"
            '';
          };
        };
    };
}
