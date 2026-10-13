# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  # For debugging
  # project_dir="/tmp/_clj-nix_cljs_project"

  setup_temp_project_vars "clj-nix_cljs_project"

  cljs_project_path="$cljnix_dir/test/clojurescript-example-project"
  cp -r "$cljs_project_path/." "$project_dir"
  init_project_flake "$cljnix_dir" "$project_dir/flake.template"
  nix run "$cljnix_dir#deps-lock"
}

# bats test_tags=cljs
@test "mkCljsApp" {
    nix_build_with_result .#mkCljsApp-test
    [ -f result/index.html ]
    [ -s result/js/main.js ]
}

# bats test_tags=cljs
@test "mkCljsApp with aliases" {
    nix_build_with_result .#mkCljsApp-test-aliases
    [ -f result/index.html ]
    [ -s result/js/main.js ]
}
