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
    # `nix flake new`, etc. Layer them on via NIX_CONFIG, and add
    # cache.garnix.io as an extra substituter so `nix build` inside
    # the bats tests can pull prebuilt artifacts (notably the
    # GraalVM-compiled babashka) instead of recompiling them in a
    # memory-constrained runner.
    export NIX_CONFIG="experimental-features = nix-command flakes
    accept-flake-config = true
    extra-substituters = https://cache.garnix.io
    extra-trusted-public-keys = cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
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

    # Podman needs a policy.json to decide which images are trusted
    # to load. Without it, `podman load` fails with "no policy.json
    # file found". For these tests we just built the images
    # ourselves via Nix in this same action, so trusting everything
    # is appropriate.
    export CONTAINERS_POLICY=$(mktemp --suffix=-policy.json)
    cat > "$CONTAINERS_POLICY" <<EOF
    { "default": [ { "type": "insecureAcceptAnything" } ] }
    EOF
    # podman 4.x reads --signature-policy and CONTAINERS_POLICY; older
    # builds may need the file at HOME/.config/containers/policy.json.
    mkdir -p "$HOME/.config/containers"
    cp "$CONTAINERS_POLICY" "$HOME/.config/containers/policy.json"

    # Default rootless networking is `pasta`, which needs
    # /dev/net/tun. The Garnix runner sandbox doesn't expose
    # /dev/net/tun, so `podman run` fails immediately. Force
    # slirp4netns instead — it's pure userspace and works without
    # /dev/net/tun.
    cat > "$HOME/.config/containers/containers.conf" <<EOF
    [network]
    default_rootless_network_cmd = "slirp4netns"
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

  # Tools every E2E action needs.
  e2eToolsBase = [
    pkgs.bats
    pkgs.nix
    pkgs.git
    pkgs.clojure
    pkgs.jdk
    pkgs.babashka
    pkgs.envsubst
    pkgs.mustache-go
    pkgs.diffutils
    pkgs.jq
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.findutils
  ];

  # Extra tools only the container-using action needs. Linux-only:
  #   shadow:       newuidmap / newgidmap for rootless podman.
  #   slirp4netns:  pasta needs /dev/net/tun, which Garnix's runner
  #                 doesn't expose. Use slirp4netns instead.
  e2eToolsPodman = [ pkgs.podman ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.shadow
      pkgs.slirp4netns
    ];

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
  # E2E apps — grouped, one Garnix Action per group.
  #
  # Earlier iteration was one-action-per-bats-file. That paid runner
  # provisioning + flake-eval + JVM startup five separate times for the
  # tiny clojurescript variants, and provisioned podman + slirp4netns +
  # shadow for seven actions that never invoke a container. Groups
  # below cluster files by setup cost and only attach the podman
  # toolchain where it's actually used.
  #
  # Adding a new .bats file? Append its filename to one of the groups
  # below. The eval-time `assert` ensures every file under test/e2e/
  # is assigned to exactly one group.
  # ---------------------------------------------------------------------
  e2eDir = ../test/e2e;

  allBatsFiles = lib.filter (n: lib.hasSuffix ".bats" n)
    (lib.attrNames (builtins.readDir e2eDir));

  e2eGroups = [
    {
      name = "clojurescript";
      files = [
        "clojurescript.bats"
        "clojurescript-aliases.bats"
        "clojurescript-install-paths.bats"
        "clojurescript-jdk.bats"
        "clojurescript-npm.bats"
      ];
      needsPodman = false;
    }
    {
      name = "jvm-projects";
      files = [
        "leiningen.bats"
        "packages.bats"
      ];
      needsPodman = false;
    }
    {
      # new-project's teardown_file calls `container_runtime rmi`, and
      # several of its tests build + load podman images (currently
      # skipped on Garnix for sandbox reasons, but the file expects
      # podman on PATH). It's the only group that needs setupPodman.
      name = "new-project";
      files = [ "new-project.bats" ];
      needsPodman = true;
    }
  ];

  groupedFiles = lib.concatMap (g: g.files) e2eGroups;
  ungroupedFiles = lib.subtractLists groupedFiles allBatsFiles;

  mkE2eName = group: "tests-e2e-${group.name}";

  mkE2eScript = group:
    let
      tools = e2eToolsBase
        ++ lib.optionals group.needsPodman e2eToolsPodman;
      podmanSetup = lib.optionalString group.needsPodman setupPodman;
      runEachFile = lib.concatMapStringsSep "\n" (file: ''
        echo ""
        echo "------------------------------------------------------"
        echo "--- bats: test/e2e/${file}"
        echo "------------------------------------------------------"
        bats --timing test/e2e/${file} || failed=$((failed + 1))
      '') group.files;
    in
    withDiagnostics (mkE2eName group) ''
      ${sandboxChecksDep}
      ${prebuiltArtifactsDep}
      ${setupEnv}
      ${setupPath tools}
      ${podmanSetup}

      failed=0
      ${runEachFile}
      if [ "$failed" -gt 0 ]; then
        echo ""
        echo "$failed bats file(s) reported failures in this action."
        exit 1
      fi
    '';

  e2eApps = lib.listToAttrs (map
    (g: {
      name = mkE2eName g;
      value = {
        type = "app";
        program = toString (mkE2eScript g);
      };
    })
    e2eGroups);

  e2eScripts = lib.listToAttrs (map
    (g: {
      name = mkE2eName g;
      value = mkE2eScript g;
    })
    e2eGroups);

in
assert lib.assertMsg (ungroupedFiles == [])
  "garnix.nix: bats files in test/e2e/ not assigned to any e2eGroup: ${toString ungroupedFiles}";
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
