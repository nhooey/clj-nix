# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  setup_temp_project_vars "cljs-install-paths-nix_project"

  cljs_project_path="$cljnix_dir/test/fixtures/example-projects/clojurescript-install-paths"
  copy_and_init_project "$cljs_project_path"
  echo "cljnixUrl: $cljnix_dir" | mustache "$project_dir/flake-template.nix" > "$project_dir/flake.nix"

  cd "$project_dir" || exit
  nix flake lock
  git init
  git add .

  nix run "$cljnix_dir#deps-lock"
  git add deps-lock.json
}

# bats test_tags=cljs,cljs-install-paths
@test "Build ClojureScript app with custom installPaths and installCommand" {
    cd "$project_dir" || exit
    nix_build_with_result .#default

    # installPaths copied the CONTENTS of resources/public into $out, so
    # shadow-cljs output at resources/public/js lands at $out/js.
    [ -f result/js/main.js ]

    # The static asset shipped in resources/public/ should also be present
    # at the $out root.
    [ -f result/index.html ]

    # installCommand ran after installPaths.
    [ -f result/install-marker.txt ]
    grep -q "installCommand-ran" result/install-marker.txt
}
