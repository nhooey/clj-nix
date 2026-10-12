# Runs the offline kaocha suites in a derivation, with every dependency
# (fixture graphs included) supplied by mkDepsCache from test/deps-lock.json.
{ pkgs, lib }:
let
  lockfile = ../deps-lock.json;
  lock = lib.importJSON lockfile;

  # `cljnix.utils/mvn-repo-info` reads Maven's _remote.repositories to tell
  # which repository an artifact came from; without it, it asks the network.
  # The ids are the ones tools.deps uses for its standard repos.
  repoName = url:
    if url == "https://repo1.maven.org/maven2/" then "central"
    else if url == "https://repo.clojars.org/" then "clojars"
    else throw "test/nix/checks.nix: no repository id for ${url}";
  remoteRepositories = lib.pipe lock.mvn-deps [
    (map (d: {
      dir = dirOf d.mvn-path;
      line = "${baseNameOf d.mvn-path}>${repoName d.mvn-repo}=\n";
    }))
    (lib.groupBy (x: x.dir))
    (lib.mapAttrsToList (dir: xs: {
      path = "${dir}/_remote.repositories";
      content = lib.concatMapStrings (x: x.line) xs;
    }))
  ];

  depsCache = pkgs.mk-deps-cache {
    inherit lockfile;
    maven-extra = remoteRepositories;
  };

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../deps.edn
      ../../tests.edn
      ../../src
      ../../pkgs
      ../../test
    ];
  };

  kaocha = name: runs: pkgs.runCommand "clj-nix-${name}"
    { nativeBuildInputs = [ pkgs.clojure pkgs.fake-git ]; }
    ''
      cp -rL ${depsCache} home
      chmod -R u+w home
      export HOME="$PWD/home"
      export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"
      export CLJ_CONFIG="$HOME/.clojure"
      export CLJ_CACHE="$PWD/cpcache"
      export GITLIBS="$HOME/.gitlibs"

      cp -r ${src} source
      chmod -R u+w source
      cd source
      ${lib.concatMapStringsSep "\n" (args: "clojure -M:test -m kaocha.runner ${args}") runs}
      touch $out
    '';
in
{
  tests-unit = kaocha "tests-unit" [
    ":unit"
    # Tagged ^:network because it clones its git deps on a cold machine;
    # here mkDepsCache supplies the checkouts. core_test's
    # missing-git-deps-test can't join it: it runs `git archive` and
    # `git remote get-url`, which need real repositories, not fake-git.
    ":network-integration --focus cljnix.nix-test/nix-hash-gitlibs-test"
  ];
  tests-integration = kaocha "tests-integration" [ ":integration" ];
}
