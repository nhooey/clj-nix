# vi: ft=sh

load helpers

setup_file() {
  bats_require_minimum_version 1.5.0

  setup_temp_project_vars

  cp -r "$cljnix_dir/test/fixtures/example-projects/git-deps/." "$project_dir"
  init_project_flake "$cljnix_dir" "$project_dir/flake-template.nix"
}

# Transitive git deps by :git/tag, and two revisions of one repo, make
# tools.deps run git while it resolves the basis.
@test "mkCljLib with transitive git deps" {
    nix_build_with_result .#mkCljLib-test
    run -0 jar tf result/gitdeps-1.0.0.jar
    [[ "$output" == *"META-INF/maven/me.lafuente/gitdeps/pom.xml"* ]]
    [[ "$output" == *"gitdeps/core.clj"* ]]
}
