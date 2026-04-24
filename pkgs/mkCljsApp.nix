/* mkCljsApp - Build a ClojureScript application

This builder creates JavaScript applications from ClojureScript projects using shadow-cljs.

OUTPUTS:
- Browser builds: Static files (HTML, JS, CSS) ready for deployment
- Node.js builds: Executable JavaScript for Node.js runtime

EXTENSIBILITY:
The build system supports custom build processes via the `buildCommand` parameter.
Default uses `clj-builder cljs-compile` with shadow-cljs.

Naming:
  name             Derivation name. Required. Plain derivation name only
                   (no "/").
  libCoordinate    Optional Maven-style org/artifact coordinate passed
                   through to clj-builder cljs-compile. Defaults to
                   "${name}/${name}".
                   Example: libCoordinate = "my-org/my-app";

Aliases:
  aliases       List of deps.edn alias names (strings) activated for the
                default build invocation. When non-empty, the default
                command becomes `clojure -M:a1:a2 <build-cmd>` — the alias
                is expected to provide `:main-opts ["-m" "shadow.cljs.devtools.cli"]`
                (the standard shadow-cljs idiom). When empty, the command
                is `clojure -M -m shadow.cljs.devtools.cli <build-cmd>`,
                assuming shadow-cljs is in top-level :deps.
                Example alias entry matching the expected shape:
                  :shadow-cljs
                    {:extra-deps {thheller/shadow-cljs {:mvn/version "..."}}
                     :main-opts  ["-m" "shadow.cljs.devtools.cli"]}
                Then pass: aliases = [ "shadow-cljs" ];

NPM / node_modules:
  npmRoot       Path containing package.json / package-lock.json. When set,
                a node_modules tree is built with importNpmLock and symlinked
                into the build dir before preBuild.
                Example: npmRoot = ./.;
  nodeModules   Escape hatch: caller-supplied pre-built node_modules
                derivation. Overrides `npmRoot` when set.
                Example: nodeModules = myCustomNodeModules;
  The resolved tree is exposed via passthru.node-modules so callers can
  reuse it for devshell watch-mode commands.

JDK:
  jdk           Optional JDK package. When non-null, the `clojure` used for
                the build is overridden to run on this JDK, and the JDK is
                added to nativeBuildInputs so `java` is available at the
                requested version. When null, the ambient `clojure` (with
                its default JDK) is used.
                Example: jdk = pkgs.jdk21;

Install layout:
  installPaths     List of relative source directories whose CONTENTS are
                   copied into $out during installPhase. Default:
                   [ "public" ], which matches the common shadow-cljs
                   browser layout of :output-dir "public/js" served from
                   public/. For other layouts, override — e.g.
                   [ "resources/public" ] for :output-dir
                   "resources/public/js".
  installCommand   Shell snippet evaluated during installPhase with $out
                   in scope. Runs after installPaths. Use for layouts
                   that don't fit the directory-contents pattern.
                   Example: installCommand = "cp dist/index.html $out/";
*/

{ stdenv
, lib
, clojure
, nodejs
, writeText
, importNpmLock

  # Custom utils
, clj-builder
, mk-deps-cache
}:

{
  # User options
  projectSrc
, name
, libCoordinate ? null
, version ? "DEV"
, buildTarget ? "browser"  # "browser" or "node"
, buildId ? "app"
, buildCommand ? null  # Override default build with custom build script
, lockfile ? null
, shadow-cljs-opts ? null
, nodejs-package ? nodejs
, aliases ? [ ]
, npmRoot ? null
, nodeModules ? null
, jdk ? null
, installPaths ? [ "public" ]
, installCommand ? null
, ...
}@attrs:

let

  extra-attrs = builtins.removeAttrs attrs [
    "projectSrc"
    "name"
    "libCoordinate"
    "version"
    "buildTarget"
    "buildId"
    "buildCommand"
    "lockfile"
    "shadow-cljs-opts"
    "nodejs-package"
    "aliases"
    "npmRoot"
    "nodeModules"
    "jdk"
    "installPaths"
    "installCommand"
    "nativeBuildInputs"
  ];

  # Optionally override clojure's JDK so the build runs on a specific JVM.
  effectiveClojure =
    if jdk != null then clojure.override { inherit jdk; } else clojure;

  # Resolve node_modules from either a caller-supplied derivation or an
  # npmRoot containing package.json + package-lock.json.
  resolvedNodeModules =
    if nodeModules != null then nodeModules
    else if npmRoot != null then
      importNpmLock.buildNodeModules {
        inherit npmRoot;
        nodejs = nodejs-package;
      }
    else null;

  deps-cache = mk-deps-cache {
    lockfile = if isNull lockfile then (projectSrc + "/deps-lock.json") else lockfile;
  };

  # `name` is the derivation name. `libCoordinate` is the Maven-style
  # org/artifact coordinate used by clj-builder cljs-compile.
  fullId = if libCoordinate != null then libCoordinate else "${name}/${name}";
  artifactId = builtins.elemAt (lib.strings.splitString "/" fullId) 1;

in
stdenv.mkDerivation ({
  inherit version;

  pname = lib.strings.sanitizeDerivationName artifactId;
  src = projectSrc;

  # Build time dependencies
  nativeBuildInputs =
    attrs.nativeBuildInputs or [ ]
      ++
      [
        effectiveClojure
        nodejs-package
      ]
      ++ lib.optional (jdk != null) jdk;

  passthru = {
    inherit deps-cache fullId artifactId buildTarget buildId;
    node-modules = resolvedNodeModules;
  };

  patchPhase =
    ''
      runHook prePatch
      ${clj-builder}/bin/clj-builder patch-git-sha "$(pwd)"
      runHook postPatch
    '';

  buildPhase =
    ''
      ${lib.optionalString (resolvedNodeModules != null) ''
        ln -s ${resolvedNodeModules}/node_modules node_modules
      ''}

      runHook preBuild

      export HOME="${deps-cache}"
      export JAVA_TOOL_OPTIONS="-Duser.home=${deps-cache}"

      # Make Node.js available for shadow-cljs (used for JavaScript processing)
      export PATH="${nodejs-package}/bin:$PATH"
    ''
    +
    (
      if builtins.isNull buildCommand then
        ''
          # Default ClojureScript build using clj-builder.
          # Trailing arg is a comma-separated list of deps.edn aliases to activate.
          ${clj-builder}/bin/clj-builder cljs-compile "${fullId}" "${version}" "${buildId}" "${buildTarget}" "${lib.concatStringsSep "," aliases}"
        ''
      else
        ''
          # Custom build command
          ${buildCommand}
        ''
    )
    +
    ''
      runHook postBuild
    '';

  installPhase =
    ''
      runHook preInstall

      mkdir -p $out

      ${lib.concatMapStringsSep "\n" (p: ''
        if [ -d "${p}" ]; then
          cp -r ${p}/. $out/
        fi
      '') installPaths}

      ${lib.optionalString (installCommand != null) installCommand}

      # For Node.js builds, create executable wrapper
      ${if buildTarget == "node" then ''
        if [ -f "$out/main.js" ]; then
          mkdir -p $out/bin
          cat > $out/bin/${artifactId} <<EOF
      #!${nodejs-package}/bin/node
      require('$out/main.js');
      EOF
          chmod +x $out/bin/${artifactId}
        fi
      '' else ""}

      runHook postInstall
    '';

  meta = {
    description = "ClojureScript application: ${name}";
    platforms = lib.platforms.all;
  };
} // extra-attrs)
