# vi: ft=sh

load helpers

setup_file() {

  bats_require_minimum_version 1.5.0

  # For debugging
  # project_dir="/tmp/_clj-nix_project"

  setup_temp_project_vars

  # Nix rejects path inputs that go through a symlink, and /tmp is one on
  # macOS, so use the physical path of the per-file temp dir.
  cljnix_dir_copy="$(cd "$BATS_FILE_TMPDIR" && pwd -P)/clj-nix_copy"
  export cljnix_dir_copy
  cp -r "$cljnix_dir" "$cljnix_dir_copy"

  nix flake new --template . "$project_dir"
  init_project_flake "$cljnix_dir_copy" "$cljnix_dir/test/integration/flake-template.nix"
  git init
  git add .
}

teardown_file() {
    $(container_runtime) rmi jvm-container-test
    $(container_runtime) rmi graal-container-test
    rm -rf "$cljnix_dir_copy"
}

@test "Generate deps-lock.json" {
    cp deps-lock.json deps-lock.json.bkp
    nix_run_and_log "$cljnix_dir#deps-lock"
    cmp deps-lock.json deps-lock.json.bkp
}

@test "New lock files are added to git" {
    git rm --cached deps-lock.json
    nix run "$cljnix_dir#deps-lock"
    git ls-files --error-unmatch deps-lock.json
}


@test "nix build .#mkCljBin-test" {
    nix_build_with_result .#mkCljBin-test
    run -0 ./result/bin/cljdemo
    [ "$output" = "Hello from CLOJURE!!!" ]
}

@test "nix build .#customJdk-test" {
    nix_build_with_result .#customJdk-test
    run -0 ./result/bin/cljdemo
    [ "$output" = "Hello from CLOJURE!!!" ]
}

@test "mkGraalBin passes extra arguments through" {
    run -0 --separate-stderr nix eval --raw .#mkGraalBin-test.nativeImageArgs --apply 'builtins.concatStringsSep " "'
    [[ " $output " == *" -J-Xmx5g "* ]]
    run -0 --separate-stderr nix eval --raw .#mkGraalBin-test.meta.description
    [ "$output" = "mkGraalBin test" ]
    run -0 --separate-stderr nix eval --raw .#mkGraalBin-test.meta.mainProgram
    [ "$output" = "cljdemo" ]
}

# bats test_tags=graal
@test "nix build .#mkGraalBin-test" {
    nix_build_with_result .#mkGraalBin-test
    run -0 ./result/bin/cljdemo
    [ "$output" = "Hello from CLOJURE!!!" ]
}

# The container tests need docker or podman. On macOS they also need a Linux
# builder (e.g. nix-darwin's nix.linux-builder), since the images are Linux
# images. Without one, skip them: tests-e2e --filter-tags '!docker'

# bats test_tags=docker
@test "nix build .#jvm-container-test" {
    nix_build_with_result .#jvm-container-test
    $(container_runtime) load -i result
    run -0 "$(container_runtime)" run --rm --network=none jvm-container-test:latest
    [ "$output" = "Hello from CLOJURE!!!" ]
}

# bats test_tags=docker,graal
@test "nix build .#graal-container-test" {
    nix_build_with_result .#graal-container-test
    $(container_runtime) load -i result
    run -0 "$(container_runtime)" run --rm --network=none graal-container-test:latest
    [ "$output" = "Hello from CLOJURE!!!" ]
}

# bats test_tags=babashka
@test "nix build .#babashka-test" {
    nix_build_with_result .#babashka-test
    run -0 ./result/bin/bb -e "(inc 101)"
    [ "$output" = "102" ]
    run ! ./result/bin/bb -e "(require '[next.jdbc])"
}

# bats test_tags=babashka
@test "nix build .#babashka-with-features-test" {
    nix_build_with_result .#babashka-with-features-test
    ./result/bin/bb -e "(require '[next.jdbc])"
}
