# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  setup_temp_project_vars "cljs-npm-nix_project"

  cljs_project_path="$cljnix_dir/test/fixtures/example-projects/clojurescript-npm"
  copy_and_init_project "$cljs_project_path"
  echo "cljnixUrl: $cljnix_dir" | mustache "$project_dir/flake-template.nix" > "$project_dir/flake.nix"

  cd "$project_dir" || exit
  nix flake lock
  git init
  git add .

  # Generate lockfile and add to git for build test
  nix run "$cljnix_dir#deps-lock"
  git add deps-lock.json
}

# bats test_tags=cljs,cljs-npm
@test "Build ClojureScript app with npm deps" {
    cd "$project_dir" || exit
    nix_build_with_result .#default
    [ -d result/js ]
    [ -f result/js/main.js ]

    # Advanced compilation strips the "left-pad" symbol but the padding
    # logic is unmistakable — check for a fragment from the left-pad
    # implementation (https://github.com/stevemao/left-pad/blob/v1.3.0/index.js).
    grep -q 'b-=c.length' result/js/main.js
}

# bats test_tags=cljs,cljs-npm
@test "node-modules is exposed via passthru" {
    cd "$project_dir" || exit
    nix_build_and_log .#default.node-modules
}
