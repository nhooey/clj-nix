# Garnix-facing apps for clj-nix CI.
#
# Each Garnix Action invokes one of the apps defined here via
# `nix run .#<app>`. The same scripts back the corresponding devShell
# commands so local and CI runs go through one code path.
#
# Imported by flake.nix; keep arguments minimal (pkgs, self, system).
{ pkgs, self, system ? "x86_64-linux" }:

let
  inherit (pkgs) lib;

  # ---------------------------------------------------------------------
  # Diagnostic file dump — runs on EXIT (success or failure) so any
  # files the test runners drop in /tmp end up in the action log
  # without needing artifact upload (decision #11).
  # ---------------------------------------------------------------------
  withDiagnostics = name: body: pkgs.writeShellScript name ''
    set -uo pipefail

    cleanup() {
      local exit_code=$?
      echo ""
      echo "======================================================"
      echo "=== Diagnostic files (captured for action logs) ==="
      echo "======================================================"
      for f in \
        /tmp/.cljnix-derivations \
        /tmp/kaocha-report.xml \
        /tmp/bats-output.tap \
        ; do
        if [ -f "$f" ]; then
          echo ""
          echo "--- $f ---"
          cat "$f" || true
        fi
      done
      exit $exit_code
    }
    trap cleanup EXIT

    ${body}
  '';

  setupEnv = ''
    export HOME=$(mktemp -d)
    export GARNIX_WORKDIR="''${GARNIX_WORKDIR:-$PWD}"
    cd "$GARNIX_WORKDIR"

    # Garnix's action-side nix config doesn't enable the experimental
    # features the bats tests need — they use `nix run`, `nix build`,
    # `nix flake new`, etc. Layer them on via NIX_CONFIG so every
    # nix invocation in this action picks them up.
    export NIX_CONFIG="experimental-features = nix-command flakes
    accept-flake-config = true"
  '';

  # ---------------------------------------------------------------------
  # Rootless podman setup — VFS storage driver, no daemon (decision #5).
  # Re-used by every E2E action.
  # ---------------------------------------------------------------------
  setupPodman = ''
    export XDG_RUNTIME_DIR=$(mktemp -d)
    export CONTAINERS_STORAGE_CONF=$(mktemp)
    cat > "$CONTAINERS_STORAGE_CONF" <<EOF
    [storage]
    driver = "vfs"
    runroot = "$XDG_RUNTIME_DIR/containers"
    graphroot = "$XDG_RUNTIME_DIR/storage"
    EOF
  '';

  # ---------------------------------------------------------------------
  # Sandbox-checks dependency comment.
  #
  # The string interpolations create real Nix build dependencies on the
  # sandbox flake checks; the surrounding `#` makes them a no-op at
  # script runtime. Garnix won't run an action whose dependency build
  # failed, so this enforces decision #3 (all actions wait for sandbox
  # checks to go green first).
  # ---------------------------------------------------------------------
  sandboxChecksDep = ''
    # Sandbox flake checks (must succeed before this action runs):
    #   tests-unit:        ${self.checks.${system}.tests-unit}
    #   tests-integration: ${self.checks.${system}.tests-integration}
  '';

  # ---------------------------------------------------------------------
  # Pre-built artifact references (decision #6).
  #
  # No first-class container packages exist in this flake — containers
  # are built dynamically by the bats tests against the dummy project
  # template. We still pin everything else Garnix can prebuild and
  # cache: the test-runner derivations, fake-git, deps-lock, babashka,
  # and the docs build. This keeps action runtime light.
  # ---------------------------------------------------------------------
  prebuiltArtifactsDep = ''
    # Prebuilt and cached by Garnix:
    #   fake-git:          ${self.packages.${system}.fake-git}
    #   deps-lock:         ${self.packages.${system}.deps-lock}
    #   babashka:          ${self.packages.${system}.babashka}
    #   test-unit:         ${self.packages.${system}.test-unit}
    #   test-integration:  ${self.packages.${system}.test-integration}
  '';

  # ---------------------------------------------------------------------
  # Tooling environments. Bake the binary path explicitly so the
  # scripts work outside `nix develop` — Garnix invokes them as plain
  # shell commands with the repo at $PWD.
  # ---------------------------------------------------------------------
  # NB: `pkgs.fake-git` is intentionally NOT on PATH here. It's a
  # babashka-backed wrapper named `git` that intercepts git commands
  # for the sandboxed deps-lock workflow. Putting it on the action's
  # PATH would shadow the real git binary and break anything that
  # genuinely needs git (the kaocha :network-integration suite clones
  # tools.build.git and reads its tags; the bats tests run `git init`
  # and `git add`). The deps-lock derivation that does need fake-git
  # gets it via its own nativeBuildInputs closure.
  cljTools = [
    pkgs.clojure
    pkgs.jdk
    pkgs.git
    pkgs.coreutils
  ];

  e2eTools = [
    pkgs.bats
    pkgs.nix
    pkgs.git
    pkgs.clojure
    pkgs.jdk
    pkgs.babashka
    pkgs.podman
    pkgs.envsubst
    pkgs.mustache-go
    pkgs.diffutils
    pkgs.jq
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.findutils
  ]
  # newuidmap / newgidmap for rootless podman — Linux only.
  ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.shadow;

  setupPath = tools: ''
    export PATH="${lib.makeBinPath tools}:$PATH"
  '';

  # ---------------------------------------------------------------------
  # tests-network — single Garnix Action covering every kaocha
  # ^:network-tagged test (decision #2).
  # ---------------------------------------------------------------------
  testsNetworkScript = withDiagnostics "tests-network" ''
    ${sandboxChecksDep}
    ${setupEnv}
    ${setupPath cljTools}
    echo "Running kaocha :network-integration suite..."
    clojure -M:test -m kaocha.runner :network-integration
  '';

  # ---------------------------------------------------------------------
  # E2E apps — one per .bats file. Discovered with builtins.readDir
  # so adding a new test file automatically creates a new Garnix
  # Action with no other code changes (then re-run the garnix.yaml
  # generator).
  # ---------------------------------------------------------------------
  e2eDir = ../test/e2e;

  batsFiles = lib.filter (n: lib.hasSuffix ".bats" n)
    (lib.attrNames (builtins.readDir e2eDir));

  mkE2eName = batsFile: "tests-e2e-${lib.removeSuffix ".bats" batsFile}";

  mkE2eScript = batsFile:
    let
      name = mkE2eName batsFile;
    in
    withDiagnostics name ''
      ${sandboxChecksDep}
      ${prebuiltArtifactsDep}
      ${setupEnv}
      ${setupPath e2eTools}
      ${setupPodman}

      echo "Running E2E test: ${batsFile}"
      bats --timing test/e2e/${batsFile}
    '';

  e2eApps = lib.listToAttrs (map
    (f: {
      name = mkE2eName f;
      value = {
        type = "app";
        program = toString (mkE2eScript f);
      };
    })
    batsFiles);

  e2eScripts = lib.listToAttrs (map
    (f: {
      name = mkE2eName f;
      value = mkE2eScript f;
    })
    batsFiles);

in
{
  apps = {
    tests-network = {
      type = "app";
      program = toString testsNetworkScript;
    };
  } // e2eApps;

  scripts = {
    tests-network = testsNetworkScript;
  } // e2eScripts;

  # Exposed for downstream code that needs to enumerate every E2E
  # action (devShell aggregator, garnix.yaml generator).
  e2eActionNames = lib.attrNames e2eApps;

  # The `tests-network` action name plus every E2E action — the full
  # set of Garnix Actions defined by this module.
  actionNames = [ "tests-network" ] ++ lib.attrNames e2eApps;
}
