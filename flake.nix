{
  description = "clj-nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-fetcher-data = {
      url = "github:jlesquembre/nix-fetcher-data";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:

    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      eachSystem = f: nixpkgs.lib.genAttrs supportedSystems (system:
        let
          pkgs = import nixpkgs
            {
              inherit system;
              overlays = [
                inputs.devshell.overlays.default
                inputs.nix-fetcher-data.overlays.default
                self.overlays.default
              ];
            };
          garnix = import ./nix/garnix.nix { inherit pkgs self system; };
        in
        f { inherit pkgs system garnix; });

      # Shared base packages for development and testing
      basePackages = pkgs: [
        pkgs.jq
        pkgs.clojure
        pkgs.babashka
        pkgs.graalvmPackages.graalvm-ce
        pkgs.bats
        pkgs.envsubst
        pkgs.mustache-go
        pkgs.diffutils
      ];

      # Additional packages needed for running tests in sandboxed builds
      testOnlyPackages = pkgs: [
        pkgs.git
        pkgs.nix
      ];

      # Helper function to create kaocha test runner command
      # Returns the base kaocha command without "$@" for use in derivations
      mkKaochaCommand = suite: "clojure -M:test -m kaocha.runner :${suite}";

      # Shared test script definitions - used by both devShells and checks
      testScripts = rec {
        unit = ''${mkKaochaCommand "unit"} "$@"'';
        integration = ''${mkKaochaCommand "integration"} "$@"'';
        network-integration = ''${mkKaochaCommand "network-integration"} "$@"'';
        e2e = ''
          bats --timing test/e2e
        '';
        all = ''
          echo "Running Clojure unit tests..."
          ${unit}
          echo "Running Clojure integration tests..."
          ${integration}
          echo "Running Clojure network integration tests..."
          ${network-integration}
          echo "Running bats end-to-end tests..."
          ${e2e}
        '';
      };
    in
    {
      packages = eachSystem ({ pkgs, system, ... }:
        let
          # Generate _remote.repositories files for Maven deps
          # Format: filename>repo-name=
          # This allows mvn-repo-info to determine which repo a dep came from
          lockData = builtins.fromJSON (builtins.readFile ./deps-lock.json);
          mavenRepoMetadata = builtins.concatMap
            ({ mvn-path, mvn-repo, ... }:
              let
                dir = builtins.dirOf mvn-path;
                filename = builtins.baseNameOf mvn-path;
                # Extract repo name from URL (central or clojars)
                repoName = if nixpkgs.lib.hasInfix "clojars" mvn-repo
                  then "clojars"
                  else "central";
                metadataPath = "${dir}/_remote.repositories";
                # Maven metadata format
                content = "${filename}>${repoName}=\n";
              in
              [{
                path = metadataPath;
                inherit content;
              }]
            )
            lockData.mvn-deps;

          # Group by path and concatenate contents for files in same directory
          groupedMetadata = nixpkgs.lib.foldl
            (acc: { path, content }:
              if builtins.hasAttr path acc
              then acc // { ${path} = acc.${path} + content; }
              else acc // { ${path} = content; }
            )
            { }
            mavenRepoMetadata;

          # Convert to list format expected by maven-extra
          mavenExtra = nixpkgs.lib.mapAttrsToList
            (path: content: { inherit path content; })
            groupedMetadata;

          # Shared deps cache for all test runners
          depsCache = pkgs.mk-deps-cache {
            lockfile = ./deps-lock.json;
            maven-extra = mavenExtra;
          };

          # Build a test runner derivation for a specific kaocha suite
          mkTestRunner = { name, suite }:
            pkgs.stdenv.mkDerivation {
              name = "clj-nix-${name}";
              src = ./.;
              nativeBuildInputs = [ pkgs.jdk pkgs.clojure pkgs.fake-git ];

              buildPhase = ''
                # Copy deps cache to writable location with proper structure
                cp -rL "${depsCache}" $TMPDIR/home
                chmod -R u+w $TMPDIR/home

                export HOME="$TMPDIR/home"
                export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"
                export CLJ_CONFIG="$HOME/.clojure"
                export CLJ_CACHE="$TMPDIR/cp_cache"
                export GITLIBS="$HOME/.gitlibs"

                # Run tests - network is blocked by Nix sandbox anyway
                ${mkKaochaCommand suite} || {
                  echo "Tests failed. Checking for missing dependencies..."
                  find $HOME/.m2/repository -name "*.part.lock" 2>/dev/null || true
                  exit 1
                }
              '';

              installPhase = ''
                mkdir -p $out
                echo "${name} passed" > $out/result
              '';
            };
        in
        {
          inherit (pkgs) deps-lock fake-git;

          babashka = pkgs.mkBabashka { };
          babashka-unwrapped = pkgs.mkBabashka { wrap = false; };

          # Variant prebuilt for the bats babashka-with-features-test
          # case, so the Garnix action runner can pull it from cache
          # instead of recompiling via GraalVM in a memory-constrained
          # sandbox.
          babashka-with-features = pkgs.mkBabashka {
            withFeatures = [ "jdbc" "sqlite" ];
          };

          docs = pkgs.callPackage ./extra-pkgs/docs { inherit pkgs; };

          # Test runners using clj-nix with locked dependencies
          test-unit = mkTestRunner {
            name = "test-unit";
            suite = "unit";
          };

          test-integration = mkTestRunner {
            name = "test-integration";
            suite = "integration";
          };

        });

      legacyPackages = eachSystem ({ pkgs, system, ... }:
        pkgs // {
          inherit (pkgs) clj-builder deps-lock mk-deps-cache
            fake-git
            mkCljBin mkCljLib mkCljsApp mkGraalBin customJdk
            cljHooks
            mkBabashka bbTasksFromFile;

          babashka = pkgs.mkBabashka { };
          babashka-unwrapped = pkgs.mkBabashka { wrap = false; };

          docs = pkgs.callPackage ./extra-pkgs/docs { inherit pkgs; };

          babashkaEnv = import ./extra-pkgs/bbenv/lib/bbenv.nix;

        });

      checks = eachSystem ({ pkgs, system, ... }:
        {
          tests-unit = self.packages.${system}.test-unit;
          tests-integration = self.packages.${system}.test-integration;
        });

      apps = eachSystem ({ garnix, ... }: garnix.apps);

      devShells = eachSystem ({ pkgs, garnix, ... }: {
        default =
          pkgs.devshell.mkShell {
            packages = basePackages pkgs;
            commands = [
              {
                name = "update-clojure-deps";
                category = "dependencies";
                help = "Update Clojure dependency versions in deps.edn";
                command = ''
                  clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' -M \
                    -m antq.core \
                    -d . \
                    --upgrade \
                    --force \
                    --skip=github-action
                '';
              }
              {
                name = "update-lock-files";
                category = "dependencies";
                help = "Regenerate all builder-lock.json and deps-lock.json files";
                command = ''
                  bb ./scripts/newer_clojure_versions.bb
                  clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' \
                    -M \
                    -m antq.core \
                    --upgrade \
                    --force
                  clj -X cljnix.bootstrap/as-json :deps-path '"deps.edn"' | jq . > pkgs/builder-lock.json
                  clj -X cljnix.core/clojure-deps-str > src/clojure-deps.edn
                  (cd ./templates/default && nix run ../..#deps-lock)
                  (cd ./test/fixtures/example-projects/leiningen && \
                    nix run ../../../..#deps-lock -- --lein --lein-profiles foobar && \
                    mv deps-lock.json deps-lock-foobar-profile.json)
                  (cd ./test/fixtures/example-projects/leiningen && \
                    nix run ../../../..#deps-lock -- --lein)
                '';
              }
              {
                name = "dummy-project";
                category = "scaffolding";
                help = "Creates a dummy clj-nix project";
                command =
                  ''
                    project_dir="$(mktemp -d clj-nix.XXXXX --tmpdir)/clj-nix_project"
                    mkdir -p "$project_dir"
                    nix flake new --template ${self} "$project_dir"
                    echo 'cljnixUrl: ${self}' | mustache "${self}/test/integration/flake-template.nix" > "$project_dir/flake.nix"
                    echo "New dummy project: $project_dir"
                  '';
              }
              {
                name = "tests-unit";
                category = "test categories";
                help = "Run Clojure unit tests";
                command = testScripts.unit;
              }
              {
                name = "tests-integration";
                category = "test categories";
                help = "Run Clojure integration tests (sandbox-compatible only)";
                command = testScripts.integration;
              }
              {
                name = "tests-network";
                category = "test categories";
                help = "Run Clojure network-requiring integration tests (one Garnix Action)";
                command = ''nix run .#tests-network -- "$@"'';
              }
              {
                name = "tests-e2e";
                category = "test categories";
                help = "Run all E2E bats tests sequentially (one Garnix Action per file in CI)";
                command = ''
                  set -e
                  failed=0
                  for app in ${pkgs.lib.concatStringsSep " " garnix.e2eActionNames}; do
                    echo ""
                    echo "=================================================="
                    echo "=== $app"
                    echo "=================================================="
                    nix run ".#$app" || failed=$((failed + 1))
                  done
                  if [ "$failed" -ne 0 ]; then
                    echo "$failed E2E action(s) failed."
                  fi
                  exit $failed
                '';
              }
              {
                name = "tests-all";
                category = "test categories";
                help = "Run all tests (Clojure and bats)";
                command = testScripts.all;
              }
              {
                name = "tests-bats";
                category = "test runners";
                help = "Run bats test runner (defaults to test/e2e directory if no args provided)";
                command = ''
                  if [ $# -eq 0 ]; then
                    bats --timing test/e2e
                  else
                    bats "$@"
                  fi
                '';
              }
              {
                name = "tests-kaocha";
                category = "test runners";
                help = "Run kaocha test runner with optional parameters";
                command = ''
                  if [ $# -eq 0 ]; then
                    clojure -M:test -m kaocha.runner
                  else
                    clojure -M:test -m kaocha.runner "$@"
                  fi
                '';
              }
            ];
          };
      });

      lib = import ./helpers.nix { clj-nix_overlay = self.overlays.default; };

      templates.default = {
        path = ./templates/default;
        description = "A simple clj-nix project";
      };

      overlays.default = final: prev:
        let common = final.callPackage ./pkgs/common.nix { }; in
        {
          fake-git = final.callPackage ./pkgs/fakeGit.nix { };
          deps-lock = final.callPackage ./pkgs/depsLock.nix { inherit common; };
          clj-builder = final.callPackage ./pkgs/cljBuilder.nix { inherit common; };
          mk-deps-cache = final.callPackage ./pkgs/mkDepsCache.nix;
          mkCljBin = final.callPackage ./pkgs/mkCljBin.nix { inherit common; };
          mkCljLib = final.callPackage ./pkgs/mkCljLib.nix { };
          mkCljsApp = final.callPackage ./pkgs/mkCljsApp.nix { };
          mkGraalBin = final.callPackage ./pkgs/mkGraalBin.nix { };
          customJdk = final.callPackage ./pkgs/customJdk.nix { };

          cljHooks = final.callPackage ./pkgs/cljHooks.nix { inherit common; };

          mkBabashka = final.callPackage ./extra-pkgs/babashka { };
          bbTasksFromFile = final.callPackage ./extra-pkgs/bbTasks { };
        }
        // inputs.nix-fetcher-data.overlays.default final prev;

    };
}
