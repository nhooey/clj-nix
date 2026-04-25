# vi: ft=sh

load helpers

setup_file() {

  bats_require_minimum_version 1.5.0

  # For debugging
  # project_dir="/tmp/_clj-nix_project"

  setup_temp_project_vars "clj-nix_project"

  cljnix_dir_copy="/tmp/_clj-nix_copy"
  export cljnix_dir_copy
  cp -r "$cljnix_dir" "$cljnix_dir_copy"

  create_project_from_template
  init_git_and_lock
}

teardown_file() {
    $(container_runtime) rmi jvm-container-test
    $(container_runtime) rmi graal-container-test
    rm -rf "$cljnix_dir_copy"
}

@test "Generate deps-lock.json" {
    backup_file deps-lock.json
    nix_run_and_log "$cljnix_dir#deps-lock"
    compare_with_backup deps-lock.json
}

@test "New lock files are added to git" {
    git rm --cached deps-lock.json
    nix run "$cljnix_dir#deps-lock"
    git ls-files --error-unmatch deps-lock.json
}


@test "nix build .#mkCljBin-test" {
    nix_build_with_result .#mkCljBin-test
    run -0 ./result/bin/cljdemo
    assert_output_equals "Hello from CLOJURE!!!"
}

@test "nix build .#customJdk-test" {
    nix_build_with_result .#customJdk-test
    run -0 ./result/bin/cljdemo
    assert_output_equals "Hello from CLOJURE!!!"
}

# bats test_tags=graal
@test "nix build .#mkGraalBin-test" {
    nix_build_with_result .#mkGraalBin-test
    run -0 ./result/bin/cljdemo
    assert_output_equals "Hello from CLOJURE!!!"
}

# bats test_tags=docker
@test "nix build .#jvm-container-test" {
    skip_if_darwin_without_remote_builders
    nix_build_with_result .#jvm-container-test
    $(container_runtime) load -i result
    # --network=none: the test container only prints a string and
    # exits, so it doesn't need networking. Garnix's runner sandbox
    # blocks /dev/net/tun, which both pasta and slirp4netns require
    # for default rootless networking.
    run -0 "$(container_runtime)" run --rm --network=none jvm-container-test:latest
    assert_output_equals "Hello from CLOJURE!!!"
}

# bats test_tags=docker,graal
@test "nix build .#graal-container-test" {
    skip_if_darwin_without_remote_builders
    nix_build_with_result .#graal-container-test
    $(container_runtime) load -i result
    # See note on jvm-container-test above re: --network=none.
    run -0 "$(container_runtime)" run --rm --network=none graal-container-test:latest
    assert_output_equals "Hello from CLOJURE!!!"
}

# bats test_tags=babashka
@test "nix build .#babashka-test" {
    # SKIP: garnix-runner-oom-on-graalvm-recompile
    # The Garnix action runner has ~4.5GB RAM, which is below what
    # GraalVM native-image needs to compile babashka (-Xmx4500m). The
    # prebuilt clj-nix.packages.<system>.babashka exists in
    # cache.garnix.io, but the dummy project's `clj-nix` path input
    # gets a different narHash under `withRepoContents: true` than
    # the Garnix prebuilder saw, so the derivation hash diverges and
    # the action recompiles from source. See MIGRATION_NOTES.md.
    skip "skipped on Garnix: babashka GraalVM rebuild OOMs (~4.5GB runner)"
    nix_build_with_result .#babashka-test
    run -0 ./result/bin/bb -e "(inc 101)"
    assert_output_equals "102"
    run ! ./result/bin/bb -e "(require '[next.jdbc])"
}

# bats test_tags=babashka
@test "nix build .#babashka-with-features-test" {
    # SKIP: garnix-runner-oom-on-graalvm-recompile (see above).
    skip "skipped on Garnix: babashka GraalVM rebuild OOMs (~4.5GB runner)"
    nix_build_with_result .#babashka-with-features-test
    ./result/bin/bb -e "(require '[next.jdbc])"
}
