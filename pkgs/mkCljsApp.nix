/* mkCljsApp - Build a ClojureScript application

This builder creates JavaScript applications from ClojureScript projects using shadow-cljs.

OUTPUTS:
- Browser builds: Static files (HTML, JS, CSS) ready for deployment
- Node.js builds: Executable JavaScript for Node.js runtime

EXTENSIBILITY:
The build system supports custom build processes via the `buildCommand` parameter.
Default uses `clj-builder cljs-compile` with shadow-cljs.

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
, ...
}@attrs:

let

  extra-attrs = builtins.removeAttrs attrs [
    "projectSrc"
    "name"
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
    "nativeBuildInputs"
  ];

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

  fullId = if (lib.strings.hasInfix "/" name) then name else "${name}/${name}";
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
        clojure
        nodejs-package
      ];

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

      # Find and copy compiled output
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

      # For Node.js builds, create executable wrapper
      ${if buildTarget == "node" then ''
        if [ -f "$out/main.js" ]; then
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
