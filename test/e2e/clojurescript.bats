# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  # For debugging
  # project_dir="/tmp/_clj-nix_cljs_project"

  setup_temp_project_vars "clj-nix_cljs_project"

  cljs_project_path="$cljnix_dir/test/fixtures/example-projects/clojurescript"
  cp -r "$cljs_project_path/." "$project_dir"
  init_project_flake "$cljnix_dir" "$project_dir/flake-template.nix"
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

# bats test_tags=cljs
@test "mkCljsApp with jdkRunner" {
    nix_build_with_result .#mkCljsApp-test-jdk
    [ -s result/js/main.js ]
    # jdk25_headless, not the default jdk (21)
    [ "$(cat result/java-version.txt)" = "25" ]
}

# bats test_tags=cljs
@test "mkCljsApp with npmRoot" {
    nix_build_with_result .#mkCljsApp-test-npm
    [ -s result/js/main.js ]
    # shadow-cljs lists the bundled sources in the manifest
    grep -qF '"node_modules/left-pad/index.js"' result/js/manifest.edn
}

# bats test_tags=cljs
@test "mkCljsApp exposes node_modules in passthru" {
    node_modules=$(nix build .#mkCljsApp-test-npm.node-modules --no-link --print-out-paths)
    echo "$node_modules" >> "$DERIVATIONS"
    [ -f "$node_modules/node_modules/left-pad/index.js" ]
}

# bats test_tags=cljs
@test "mkCljsApp with nodeModules" {
    nix_build_with_result .#mkCljsApp-test-node-modules
    grep -qF '"node_modules/left-pad/index.js"' result/js/manifest.edn
}
