# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  # For debugging
  # project_dir="/tmp/_clj-nix_project"

  setup_temp_project_vars

  leiningen_project_path="$cljnix_dir/test/leiningen-example-project"
  cp -r "$leiningen_project_path/." "$project_dir"
  init_project_flake "$cljnix_dir" "$project_dir/flake.template"
  ls -la
  cat flake.nix
}

# bats test_tags=lein
@test "Generate lockfile (leiningen)" {
    cp deps-lock.json deps-lock.json.bkp
    nix_run_and_log "$cljnix_dir#deps-lock" --lein
    cmp deps-lock.json deps-lock.json.bkp
}

# bats test_tags=lein
@test "Generate lockfile for specific Leiningen profile only (leiningen)" {
    cp deps-lock.json deps-lock.json.bkp
    nix_run_and_log "$cljnix_dir#deps-lock" --lein --lein-profiles foobar
    cmp deps-lock.json deps-lock-foobar-profile.json
    cp deps-lock.json.bkp deps-lock.json
}

# bats test_tags=lein
@test "mkCljBin (leiningen)" {
    skip
    nix_build_with_result .#mkCljBin-test
    run -0 ./result/bin/cljdemo
    [ "$output" = "Hello, World!" ]
}

# bats test_tags=lein
@test "mkCljBin with tests (leiningen)" {
    skip
    nix_build_with_result .#mkCljBin-test-with-tests
    run -0 ./result/bin/cljdemo
    [ "$output" = "Hello, World!" ]
}
