{pkgs}: pkgs.runCommand "workflow-smoke" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  workflow=${../.github/workflows/sync-profile.yml}

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
''
