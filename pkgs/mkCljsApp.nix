/* mkCljsApp - Build a ClojureScript application

This builder creates JavaScript applications from ClojureScript projects using shadow-cljs.

OUTPUTS:
- Browser builds: Static files (HTML, JS, CSS) ready for deployment
- Node.js builds: Executable JavaScript for Node.js runtime

EXTENSIBILITY:
The build system supports custom build processes via the `buildCommand` parameter.
Default uses `clj-builder cljs-compile` with shadow-cljs.

Naming:
  name             Derivation name. Required. Must be a plain derivation name
                   (no "/"). Historically this argument was overloaded to
                   carry a Maven-style org/artifact coordinate when it
                   contained "/"; that form still works but emits a
                   deprecation warning.
  libCoordinate    Optional org/artifact coordinate passed through to
                   clj-builder cljs-compile. Defaults to "${name}/${name}".
                   Example: libCoordinate = "my-org/my-app";

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

JDK:
  jdk           Optional JDK package. When non-null, the `clojure` used for
                the build is overridden to run on this JDK, and the JDK is
                added to nativeBuildInputs so `java` is available at the
                requested version. When null, the ambient `clojure` (with
                its default JDK) is used.
                Example: jdk = pkgs.jdk21;

Install layout:
  installPaths     List of relative source paths copied into $out during
                   installPhase. When null, falls back to the legacy
                   "target/cljs/<buildId>" then "public/" then any
                   target/..js search. installPaths and installCommand are
                   orthogonal: installPaths runs first, then installCommand
                   (if set).
                   Example: installPaths = [ "resources/public" ];
  installCommand   Full override of the installPhase copy logic. Receives
                   $out in scope. Runs after installPaths (when both set).
                   Example: installCommand = "cp -r dist/. $out/";
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
, npmRoot ? null
, nodeModules ? null
, aliases ? [ ]
, jdk ? null
, installPaths ? null
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
    "npmRoot"
    "nodeModules"
    "aliases"
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

  # `name` is the derivation name. libCoordinate is the Maven-style
  # org/artifact coordinate used by clj-builder cljs-compile. For backwards
  # compatibility, a slash in `name` is still accepted as a coordinate but
  # emits a deprecation warning.
  nameHasSlash = lib.strings.hasInfix "/" name;
  fullId =
    if libCoordinate != null then libCoordinate
    else if nameHasSlash then
      lib.warn
        ("mkCljsApp: passing an org/artifact coordinate via `name` is deprecated; "
        + "use `libCoordinate = \"" + name + "\";` and set `name` to a plain derivation name.")
        name
    else "${name}/${name}";
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

      ${if installPaths != null then
          lib.concatMapStringsSep "\n" (p: ''
            if [ -e "${p}" ]; then
              cp -r ${p} $out/
            fi
          '') installPaths
        else ''
          # Legacy fallback: find and copy compiled output from conventional locations
          if [ -d "target/cljs/${buildId}" ]; then
            cp -r target/cljs/${buildId}/* $out/
          elif [ -d "public" ]; then
            # shadow-cljs default output for browser builds
            cp -r public/* $out/
          else
            echo "Warning: No compiled output found in expected locations"
            # Copy any .js files found in target
            find target -name "*.js" -exec cp {} $out/ \;
          fi
        ''}

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
