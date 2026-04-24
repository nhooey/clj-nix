# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  setup_temp_project_vars "cljs-legacy-name-nix_project"

  cljs_project_path="$cljnix_dir/test/fixtures/example-projects/clojurescript-legacy-name"
  copy_and_init_project "$cljs_project_path"
  echo "cljnixUrl: $cljnix_dir" | mustache "$project_dir/flake-template.nix" > "$project_dir/flake.nix"

  cd "$project_dir" || exit
  nix flake lock
  git init
  git add .

  nix run "$cljnix_dir#deps-lock"
  git add deps-lock.json
}

# bats test_tags=cljs,cljs-legacy-name
@test "Build with deprecated slash-in-name still succeeds" {
    cd "$project_dir" || exit
    nix_build_with_result .#default
    [ -d result/js ]
}

# bats test_tags=cljs,cljs-legacy-name
@test "Deprecation warning is emitted for slash-in-name" {
    cd "$project_dir" || exit
    # Evaluate the flake and capture stderr; lib.warn goes to stderr.
    run nix eval --raw .#default.drvPath 2>&1
    echo "$output" | grep -q "deprecated"
    echo "$output" | grep -q "libCoordinate"
}
