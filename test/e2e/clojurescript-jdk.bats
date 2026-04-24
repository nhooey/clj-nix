# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  setup_temp_project_vars "cljs-jdk-nix_project"

  cljs_project_path="$cljnix_dir/test/fixtures/example-projects/clojurescript-jdk"
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

# bats test_tags=cljs,cljs-jdk
@test "Build ClojureScript app with pinned jdk21" {
    cd "$project_dir" || exit
    nix_build_with_result .#default
    [ -d result/js ]
    [ -f result/jdk-used.txt ]

    # jdk21 should identify as "openjdk version 21..."
    grep -q 'version "21' result/jdk-used.txt
}
