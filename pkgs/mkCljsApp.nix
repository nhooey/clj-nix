{
  stdenv,
  lib,
  clojure,
  nodejs,
  importNpmLock,

  # Default JDK
  jdk,

  # Custom utils
  clj-builder,
  fake-git,
  mk-deps-cache,
}:

{
  # User options
  jdkRunner ? jdk, # JDK that runs the build (Clojure CLI and shadow-cljs)
  projectSrc,
  name,
  version ? "DEV",
  buildId ? "app",
  aliases ? [ ],
  buildCommand ? null,
  lockfile ? null,
  installPaths ? [ "public" ],
  npmRoot ? null,
  nodeModules ? null,

  # Needed for version ranges
  maven-extra ? [ ],
  ...
}@attrs:

let

  extra-attrs = builtins.removeAttrs attrs [
    "jdkRunner"
    "projectSrc"
    "name"
    "version"
    "buildId"
    "aliases"
    "buildCommand"
    "lockfile"
    "installPaths"
    # Not in the environment: linkNodeModulesHook would cd into $npmRoot
    "npmRoot"
    "nodeModules"
    "maven-extra"
    "nativeBuildInputs"
    "passthru"
  ];

  deps-cache = mk-deps-cache {
    lockfile = if isNull lockfile then (projectSrc + "/deps-lock.json") else lockfile;
    inherit maven-extra;
  };

  # node_modules from package-lock.json, one fixed-output fetch per package
  # (hashes from the lock file's `integrity` fields)
  resolvedNodeModules =
    if nodeModules != null then
      nodeModules
    else if npmRoot != null then
      importNpmLock.buildNodeModules {
        inherit npmRoot nodejs;
      }
    else
      null;
  hasNodeModules = resolvedNodeModules != null;

  builder = clj-builder.override { jdk = jdkRunner; };

  fullId = if (lib.strings.hasInfix "/" name) then name else "${name}/${name}";
  artifactId = builtins.elemAt (lib.strings.splitString "/" fullId) 1;

  # With aliases, the alias provides shadow-cljs' :main-opts
  # (["-m" "shadow.cljs.devtools.cli"]), so we don't add `-m` ourselves
  shadowCmd =
    if aliases == [ ] then
      "clojure -M -m shadow.cljs.devtools.cli"
    else
      "clojure -M:${lib.escapeShellArg (lib.concatStringsSep ":" aliases)}";

in
stdenv.mkDerivation (
  {
    inherit version;

    pname = lib.strings.sanitizeDerivationName artifactId;
    src = projectSrc;

    # Build time deps. A release build of a browser target runs on the JVM
    # only; add Node.js through nativeBuildInputs if buildCommand needs it.
    nativeBuildInputs =
      attrs.nativeBuildInputs or [ ]
      ++ [
        fake-git
        (clojure.override { jdk = jdkRunner; })
      ]
      # Links $npmDeps/node_modules/* into ./node_modules before configure,
      # and puts node_modules/.bin on PATH
      ++ lib.optional hasNodeModules importNpmLock.linkNodeModulesHook;

    passthru = {
      inherit deps-cache fullId artifactId;
      node-modules = resolvedNodeModules;
    }
    // (attrs.passthru or { });

    preBuildPhases = [ "preBuildPhase" ];
    preBuildPhase =
      (lib.strings.optionalString (!isNull lockfile) ''
        cp "${lockfile}" deps-lock.json
      '')
      + ''
        ${builder}/bin/clj-builder patch-git-sha "$(pwd)"
      '';

    # Same Clojure environment as mkCljBin, see the links there
    buildPhase = ''
      runHook preBuild

      export HOME="$TMP/clj-home"
      mkdir -p "$HOME"
      cp -rL "${deps-cache}/." "$HOME/"
      chmod -R u+w "$HOME"

      export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"

      export CLJ_CONFIG="$HOME/.clojure"
      export CLJ_CACHE="$TMP/cp_cache"
      export GITLIBS="$HOME/.gitlibs"
    ''
    + (
      if builtins.isNull buildCommand then
        ''
          ${shadowCmd} release ${lib.escapeShellArg buildId}
        ''
      else
        ''
          ${buildCommand}
        ''
    )
    + ''
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
    ''
    + lib.concatMapStrings (path: ''
      if [ ! -d ${lib.escapeShellArg path} ]; then
        echo "mkCljsApp: installPaths entry is not a directory:" ${lib.escapeShellArg path} >&2
        exit 1
      fi
      cp -r ${lib.escapeShellArg path}/. $out/
    '') installPaths
    + ''
      runHook postInstall
    '';
  }
  // lib.optionalAttrs hasNodeModules {
    # Read by linkNodeModulesHook
    npmDeps = resolvedNodeModules;

    # linkNodeModulesHook only logs and skips entries of an existing
    # node_modules, so a stale local install would be used silently
    preConfigurePhases = [ "nodeModulesCheckPhase" ];
    nodeModulesCheckPhase = ''
      if [ -e node_modules ]; then
        echo "mkCljsApp: projectSrc already contains node_modules; exclude it from the source (npmRoot/nodeModules provide it)" >&2
        exit 1
      fi
    '';
  }
  // extra-attrs
)
