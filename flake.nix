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
            name: scriptPath: envVars:
            pkgs.runCommand name ({ nativeBuildInputs = [ pkgs.python3 ]; } // envVars) ''
              ${pkgs.python3}/bin/python3 ${scriptPath}
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

            "profile-schema" = mkPythonCheck "profile-schema" ./tests/profile-schema.py {
              COMMITTED_STATE = committedReposState;
              EXPECTED_TEXT = schemaFixtureExpectedText;
              EXPECTED_STATE = schemaFixtureExpectedState;
              INVALID_PARTIAL_DIR = invalidPartialFixtureDir;
              SYNC_SCRIPT = ./scripts/sync-profile.py;
              SCHEMA_FIXTURE_DIR = schemaFixtureDir;
            };

            "self-idempotence" = mkPythonCheck "self-idempotence" ./tests/self-idempotence.py {
              FIXTURE_DIR = selfIdempotenceFixtureDir;
              EXPECTED_TEXT = selfIdempotenceExpectedText;
              EXPECTED_STATE = selfIdempotenceExpectedState;
              SYNC_SCRIPT = ./scripts/sync-profile.py;
            };

            "pagination-fixture" = mkPythonCheck "pagination-fixture" ./tests/pagination-fixture.py {
              SYNC_SCRIPT = ./scripts/sync-profile.py;
              PAGE1 = paginationPage1;
              PAGE2 = paginationPage2;
            };
            "workflow-smoke" = import ./tests/workflow-smoke.nix { inherit pkgs; };
          };
        };
    };
}

