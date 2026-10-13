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

  outputs =
    { self, nixpkgs, ... }@inputs:

    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      eachSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [
                inputs.devshell.overlays.default
                inputs.nix-fetcher-data.overlays.default
                self.overlays.default
              ];
            };
            inherit system;
          }
        );
    in
    {
      packages = eachSystem (
        { pkgs, system }:
        {
          inherit (pkgs) clj-builder deps-lock fake-git;

          babashka = pkgs.mkBabashka { };

          docs = pkgs.callPackage ./extra-pkgs/docs { inherit pkgs; };
        }
      );

      # `packages` may only hold derivations (`nix flake check` rejects
      # anything else), so the builder functions live here, next to the
      # packages above.
      legacyPackages = eachSystem (
        { pkgs, system }:
        self.packages.${system}
        // {
          inherit (pkgs)
            mk-deps-cache
            mkCljBin
            mkCljLib
            mkCljsApp
            mkGraalBin
            customJdk
            cljHooks
            mkBabashka
            bbTasksFromFile
            ;

          babashkaEnv = import ./extra-pkgs/bbenv/lib/bbenv.nix;
        }
      );

      checks = eachSystem (
        { pkgs, ... }:
        import ./test/nix/checks.nix {
          inherit pkgs;
          inherit (nixpkgs) lib;
        }
      );

      devShells = eachSystem (
        { pkgs, ... }: {
          default = pkgs.devshell.mkShell {
            packages = [
              pkgs.jq
              pkgs.clojure
              pkgs.babashka
              pkgs.graalvmPackages.graalvm-ce
              pkgs.envsubst
              pkgs.mustache-go
              pkgs.diffutils
              pkgs.clj-kondo
            ];
            commands = [
              {
                name = "update-deps";
                category = "dependencies";
                help = "Update dependency versions and regenerate the lock files";
                command = ''
                  bb ./scripts/newer_clojure_versions.bb
                  bb ./scripts/update_maven_jar.bb pkgs/graal-build-time.json
                  clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' -M -m antq.core --upgrade --force --skip=github-action
                  clj -X cljnix.bootstrap/as-json :deps-path '"deps.edn"' | jq . > pkgs/builder-lock.json
                  clj -X cljnix.core/clojure-deps-str > src/clojure-deps.edn
                  (cd ./templates/default && nix run ../..#deps-lock)
                  (cd ./test/fixtures/example-projects/leiningen && nix run ../../../..#deps-lock -- --lein --lein-profiles foobar && mv deps-lock.json deps-lock-foobar-profile.json)
                  (cd ./test/fixtures/example-projects/leiningen && nix run ../../../..#deps-lock -- --lein)
                  (cd ./test && nix run ..#deps-lock -- --deps-include ../deps.edn $(printf -- '--deps-include %s ' fixtures/deps-graphs/*/deps.edn))
                '';
              }
              {
                name = "kaocha";
                category = "test runners";
                help = "Run tests with kaocha";
                command = ''
                  clojure -M:test -m kaocha.runner "$@"
                '';
              }
              {
                name = "bats";
                category = "test runners";
                help = "Run tests with bats (default: bats --timing test/e2e)";
                command = ''
                  if [ $# -eq 0 ]; then
                    exec ${pkgs.bats}/bin/bats --timing test/e2e
                  else
                    exec ${pkgs.bats}/bin/bats "$@"
                  fi
                '';
              }
              {
                name = "lint";
                category = "test runners";
                help = "Lint Clojure code with clj-kondo (fails on errors)";
                command = ''
                  # Analyse the classpath first: imports the configs that
                  # dependencies export (macros like babashka.fs/with-temp-dir)
                  # and caches their vars (arities, deprecations)
                  clj-kondo --lint "$(clojure -Spath -M:test)" --dependencies --parallel --copy-configs
                  clj-kondo --lint src test pkgs scripts --fail-level error "$@"
                '';
              }
              {
                name = "tests-unit";
                category = "tests";
                help = "Run Clojure unit tests";
                command = ''
                  kaocha :unit "$@"
                '';
              }
              {
                name = "tests-integration";
                category = "tests";
                help = "Run Clojure integration tests";
                command = ''
                  kaocha :integration "$@"
                '';
              }
              {
                name = "tests-network";
                category = "tests";
                help = "Run Clojure tests that need network access";
                command = ''
                  kaocha :network-integration "$@"
                '';
              }
              {
                name = "tests-e2e";
                category = "tests";
                help = "Run end-to-end tests with bats";
                command = ''
                  exec ${pkgs.bats}/bin/bats --timing test/e2e "$@"
                '';
              }
              {
                name = "tests-all";
                category = "tests";
                help = "Run unit, integration, network and end-to-end tests";
                command = ''
                  tests-unit && tests-integration && tests-network && tests-e2e
                '';
              }
              {
                name = "dummy-project";
                category = "scaffolding";
                help = "Creates a dummy clj-nix project";
                command = ''
                  project_dir="$(mktemp -d clj-nix.XXXXX --tmpdir)/clj-nix_project"
                  mkdir -p "$project_dir"
                  nix flake new --template ${self} "$project_dir"
                  echo 'cljnixUrl: ${self}' | mustache "${self}/test/integration/flake-template.nix" > "$project_dir/flake.nix"
                  echo "New dummy project: $project_dir"
                '';
              }
            ];
          };
        }
      );

      lib = import ./helpers.nix { clj-nix_overlay = self.overlays.default; };

      templates.default = {
        path = ./templates/default;
        description = "A simple clj-nix project";
      };

      overlays.default =
        final: prev:
        let
          common = final.callPackage ./pkgs/common.nix { };
        in
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
