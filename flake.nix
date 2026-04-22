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

      eachSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs
          {
            inherit system;
            overlays = [
              inputs.devshell.overlays.default
              inputs.nix-fetcher-data.overlays.default
              self.overlays.default
            ];
          };
        inherit system;
      });

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

      # Shared test script definitions - used by both devShells and checks
      testScripts = rec {
        unit = ''
          clojure -M:test -m kaocha.runner :unit "$@"
        '';
        integration = ''
          clojure -M:test -m kaocha.runner :integration "$@"
        '';
        e2e = ''
          bats --timing test
        '';
        all = ''
          echo "Running Clojure unit tests..."
          ${unit}
          echo "Running Clojure integration tests..."
          ${integration}
          echo "Running bats end-to-end tests..."
          ${e2e}
        '';
      };
    in
    {
      packages = eachSystem ({ pkgs, system }:
        let
          # Shared deps cache for all test runners
          depsCache = pkgs.mk-deps-cache {
            lockfile = ./deps-lock.json;
          };

          # Build a test runner derivation for a specific kaocha suite
          mkTestRunner = { name, kaochaArgs }:
            pkgs.stdenv.mkDerivation {
              name = "clj-nix-${name}";
              src = ./.;
              nativeBuildInputs = [ pkgs.jdk pkgs.clojure pkgs.fake-git ];

              buildPhase = ''
                # Copy deps cache to writable location
                cp -r "${depsCache}" $TMPDIR/home
                chmod -R u+w $TMPDIR/home

                export HOME="$TMPDIR/home"
                export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"
                export CLJ_CONFIG="$HOME/.clojure"
                export CLJ_CACHE="$TMPDIR/cp_cache"
                export GITLIBS="$HOME/.gitlibs"

                clojure -M:test -m kaocha.runner ${kaochaArgs}
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

          docs = pkgs.callPackage ./extra-pkgs/docs { inherit pkgs; };

          # Test runners using clj-nix with locked dependencies
          test-unit = mkTestRunner {
            name = "test-unit";
            kaochaArgs = ":unit";
          };

          test-integration = mkTestRunner {
            name = "test-integration";
            kaochaArgs = ":integration";
          };

        });

      legacyPackages = eachSystem ({ pkgs, system }:
        pkgs // {
          inherit (pkgs) clj-builder deps-lock mk-deps-cache
            fake-git
            mkCljBin mkCljLib mkGraalBin customJdk
            cljHooks
            mkBabashka bbTasksFromFile;

          babashkaEnv = import ./extra-pkgs/bbenv/lib/bbenv.nix;
        });

      checks = eachSystem ({ pkgs, ... }:
        {
          # Unit tests using clj-nix with locked dependencies (no network needed)
          tests-unit = self.packages.${pkgs.system}.test-unit;

          # Integration tests using clj-nix with locked dependencies (no network needed)
          tests-integration = self.packages.${pkgs.system}.test-integration;

          # E2E tests still need nix commands, so use script-based approach
          tests-e2e = pkgs.stdenv.mkDerivation {
            name = "clj-nix-tests-e2e";
            src = self;
            buildInputs = basePackages pkgs ++ testOnlyPackages pkgs;

            buildPhase = ''
              export HOME=$TMPDIR
              ${testScripts.e2e}
            '';

            installPhase = ''
              mkdir -p $out
              echo "Tests passed" > $out/result
            '';
          };
        });

      devShells = eachSystem ({ pkgs, ... }: {
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
                  (cd ./test/leiningen-example-project && \
                    nix run ../..#deps-lock -- --lein --lein-profiles foobar && \
                    mv deps-lock.json deps-lock-foobar-profile.json)
                  (cd ./test/leiningen-example-project && \
                    nix run ../..#deps-lock -- --lein)
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
                    echo 'cljnixUrl: ${self}' | mustache "${self}/test/integration/flake.template" > "$project_dir/flake.nix"
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
                help = "Run Clojure integration tests";
                command = testScripts.integration;
              }
              {
                name = "tests-e2e";
                category = "test categories";
                help = "Run end-to-end tests with bats";
                command = testScripts.e2e;
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
                help = "Run bats test runner (defaults to test directory if no args provided)";
                command = ''
                  if [ $# -eq 0 ]; then
                    bats --timing test
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
          mkGraalBin = final.callPackage ./pkgs/mkGraalBin.nix { };
          customJdk = final.callPackage ./pkgs/customJdk.nix { };

          cljHooks = final.callPackage ./pkgs/cljHooks.nix { inherit common; };

          mkBabashka = final.callPackage ./extra-pkgs/babashka { };
          bbTasksFromFile = final.callPackage ./extra-pkgs/bbTasks { };
        }
        // inputs.nix-fetcher-data.overlays.default final prev;

    };
}
