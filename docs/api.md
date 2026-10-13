# API

The builder functions below come from `overlays.default` or from
`clj-nix.legacyPackages.${system}`.

## Derivations

- [mkCljBin](#mkcljbin): Creates a clojure application
- [customJdk](#customjdk): Creates a custom JDK with jlink. Optionally takes a
  derivation created with `mkCljBin`. The intended use case is to create a
  minimal JDK you can deploy in a container (e.g: a Docker image)
- [mkGraalBin](#mkgraalbin): Creates a binary with GraalVM from a derivation
  created with `mkCljBin`
- [mkCljLib](#mkcljlib): Creates a clojure library jar
- [mkCljsApp](#mkcljsapp): Creates a ClojureScript application with
  [shadow-cljs](https://github.com/thheller/shadow-cljs)
- [mkBabashka](#mkBabashka): Builds custom
  [babashka](https://github.com/babashka/babashka)

!!! note

    Extra unknown attributes are passed to the `mkDerivation` function,
    see [mkCljBin](#mkcljbin) section for an example about how to add a custom check
    phase.

### mkCljBin

Creates a Clojure application. Takes the following attributes (those without a
default are mandatory, extra attributes are passed to **mkDerivation**):

- **jdkRunner**: JDK used at runtime by the application. (Default: `jdk`)

- **projectSrc**: Project source code.

- **name**: Derivation and clojure project name. It's recommended to use a
  namespaced name. If not, a namespace is added automatically. E.g. `foo` will
  be transformed to `foo/foo`

- **version**: Derivation and clojure project version. (Default: `DEV`)

- **main-ns**: Main clojure namespace. A `-main` function is expected here.
  `main-ns` file must include the `:gen-class` directive, e.g.:
  `(ns foo (:gen-class))`. That's required to generate a valid uberjar,
  `clj-nix` does a check for it.

- **buildCommand**: Command to build the jar application. If not provided, a
  default builder is used:
  [build.clj](https://github.com/jlesquembre/clj-nix/blob/main/src/cljnix/build.clj).
  If you provide your own build command, you can define the path to the final
  uberjar with the `jarPath` environment variable (e.g.:
  `export jarPath=$BUILD_DIR/my_uber.jar`). If `jarPath` is undefined, `clj-nix`
  looks for a jar file in a directory called `target`, preferring one whose
  name ends in `-standalone.jar`.

- **lockfile**: The lock file. (Default: `${projectSrc}/deps-lock.json`)

- **java-opts**: List of Java options to include the application wrapper, e.g.:
  `[ "-Djava.awt.headless=true" ]`. (Default: `[ ]`)

- **compileCljOpts**: Override options passed to
  [`compile-clj`](https://clojure.github.io/tools.build/clojure.tools.build.api.html#var-compile-clj).
  (Default: `null`)

- **javacOpts**: Options passed to
  [`javac`](https://clojure.github.io/tools.build/clojure.tools.build.api.html#var-javac).
  Needed if the projects contains java source files. Only 2 options are
  supported: `src-dirs` and `javac-opts`. (Default: `null`)

- **uberOpts**: Options passed to
  [`uber`](https://clojure.github.io/tools.build/clojure.tools.build.api.html#var-uber)
  See [TBUILD-11](https://clojure.atlassian.net/browse/TBUILD-11) for when you might need it.
  Only 1 option is supported: `exclude`. (Default: `null`)

- **enableLeiningen**: Makes Leiningen accessible at build time (Default:
  `false`)

- **builder-extra-inputs**: Extra inputs to the default builder (Default: `[ ]`)

- **builder-java-opts** List of Java options to include in default builder
  command (Default: `[ ]`)

- **builder-preBuild** Pre build commands for the default builder (Default:
  `""`)
- **builder-postBuild** Post build commands for the default builder (Default:
  `""`)

!!! note

    The `builder-*` options (`builder-extra-inputs`, `builder-java-opts`,
    `builder-preBuild`, `builder-postBuild`) are incompatible with the
    `buildCommand` option. Use either the default builder with `builder-*`
    options or provide a custom `buildCommand`, but not both.

**Example**:

```nix
mkCljBin {
  jdkRunner = pkgs.jdk_headless;
  projectSrc = ./.;
  name = "me.lafuente/clj-tuto";
  version = "1.0";
  main-ns = "demo.core";

  buildCommand = "clj -T:build uber";

  # mkDerivation attributes
  doCheck = true;
  checkPhase = "clj -M:test";
}
```

**Outputs**:

- **out**: The application binary
- **lib**: The application jar

### customJdk

Creates a custom JDK runtime. Takes the following attributes (those without a
default are mandatory):

- **jdkBase**: JDK used to build the custom JDK with jlink. (Default:
  `nixpkgs.jdk_headless`)

- **cljDrv**: Derivation generated with `mkCljBin`.

- **name**: Derivation name. (Default: `cljDrv.name`)

- **version**: Derivation version. (Default: `cljDrv.version`)

- **java-opts**: List of Java options to include the application wrapper, e.g.:
  `[ "-Djava.awt.headless=true" ]`. (Default: `[ ]`)

- **jdkModules**: Option passed to jlink `--add-modules`. If null,
  [`jeps`](https://docs.oracle.com/en/java/javase/17/docs/specs/man/jdeps.html)
  will be used to analyze the `cljDrv` and pick the necessary modules
  automatically. (Default: `null`)

- **extraJdkModules**: Extra JDK modules appended to `jdkModules`. (Default:
  `[ ]`)

- **locales**: Option passed to jlink `--include-locales`. (Default: `null`)

**Example**:

```nix
customJdk {
  jdkBase = pkgs.jdk_headless;
  name = "myApp";
  version = "1.0.0";
  cljDrv = myCljBinDerivation;
  locales = "en,es";
}
```

**Outputs**:

- **out**: The application binary, using the custom JDK
- **jdk**: The custom JDK

### mkGraalBin

Generates a binary with GraalVM from an application created with `mkCljBin`.
Takes the following attributes (those without a default are mandatory):

- **cljDrv**: Derivation generated with `mkCljBin`.

- **graalvm**: GraalVM used at build time. (Default: `nixpkgs.graalvmPackages.graalvm-ce`)

- **name**: Derivation name. (Default: `cljDrv.name`)

- **version**: Derivation version. (Default: `cljDrv.version`)

- Options passed to nixpkgs
  [buildGraalvmNativeImage](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/build-graalvm-native-image/default.nix):
  **nativeBuildInputs**, **nativeImageBuildArgs**,
  **extraNativeImageBuildArgs**, **graalvmXmx**, **meta**. Empty options are
  ignored.

**Example**:

```nix
mkGraalBin {
  cljDrv = myCljBinDerivation;
}
```

### mkCljLib

Creates a jar file for a Clojure library. Takes the following attributes (those
without a default are mandatory, extra attributes are passed to
**mkDerivation**):

- **jdkRunner**: JDK used to build the library: it runs the builder and
  `buildCommand`, and compiles any Java sources. (Default: `jdk`)

- **projectSrc**: Project source code.

- **name**: Derivation and clojure library name. It's recommended to use a
  namespaced name. If not, a namespace is added automatically. E.g. `foo` will
  be transformed to `foo/foo`

- **version**: Derivation and clojure project version. (Default: `DEV`)

- **buildCommand**: Command to build the jar application. If not provided, a
  default builder is used:
  [jar fn in build.clj](https://github.com/jlesquembre/clj-nix/blob/main/src/cljnix/build.clj).
  If you provide your own build command, clj-nix expects that a jar will be
  generated in a directory called `target`

**Example**:

```nix
mkCljLib {
  jdkRunner = pkgs.jdk17_headless;
  projectSrc = ./.;
  name = "me.lafuente/my-lib";
  buildCommand = "clj -T:build jar";
}
```

### mkCljsApp

Creates a ClojureScript application, compiled with a
[shadow-cljs](https://github.com/thheller/shadow-cljs) release build. Takes the
following attributes (those without a default are mandatory, extra attributes
are passed to **mkDerivation**):

- **projectSrc**: Project source code. It needs a `deps.edn` with
  `thheller/shadow-cljs` in its dependencies, and a `shadow-cljs.edn` with the
  build.

- **name**: Derivation and ClojureScript project name. It's recommended to use
  a namespaced name. If not, a namespace is added automatically. E.g. `foo`
  will be transformed to `foo/foo`

- **version**: Derivation and ClojureScript project version. (Default: `DEV`)

- **buildId**: Build id in `shadow-cljs.edn`. (Default: `app`)

- **aliases**: List of `deps.edn` aliases (strings, without the `:`) used to
  run shadow-cljs. If empty, the build runs
  `clojure -M -m shadow.cljs.devtools.cli release <buildId>`, so shadow-cljs
  must be in the top-level `:deps`. Otherwise it runs
  `clojure -M:<alias1>:<alias2> release <buildId>`, and one of the aliases
  must set `:main-opts ["-m" "shadow.cljs.devtools.cli"]`, as the shadow-cljs
  documentation suggests. (Default: `[ ]`)

- **buildCommand**: Command to build the application. If provided, it replaces
  the shadow-cljs command above. The build has no network access, so it can't
  run `npx shadow-cljs`; use the Clojure CLI instead, e.g.
  `clojure -M:shadow-cljs release app`.

- **lockfile**: The lock file. (Default: `${projectSrc}/deps-lock.json`)

- **installPaths**: List of directories, relative to the project root, whose
  contents are copied to the output. The build fails if one of them doesn't
  exist. The default matches the usual browser layout, with
  `:output-dir "public/js"` served from `public/`. (Default: `[ "public" ]`)

- **npmRoot**: Directory with the `package.json` and `package-lock.json` of the
  npm packages the build requires. `node_modules` is built from the lock file
  with nixpkgs'
  [importNpmLock](https://nixos.org/manual/nixpkgs/unstable/#javascript-buildNpmPackage-importNpmLock)
  and linked into the project root, where shadow-cljs looks for it. No extra
  hash is needed: each package is fetched with its `integrity` hash from the
  lock file. `projectSrc` must not contain a `node_modules` directory.
  (Default: `null`)

- **nodeModules**: A derivation with a `node_modules` directory, used instead
  of building one from `npmRoot`, e.g. from
  `pkgs.importNpmLock.buildNodeModules` with other options. (Default: `null`)

The `node_modules` derivation is available as `passthru.node-modules`.

The build runs on the JVM only. If your `buildCommand` needs Node.js, add it
with `nativeBuildInputs = [ pkgs.nodejs ];`.

!!! note "Maintainer"

    `mkCljsApp` is maintained by [@nhooey](https://github.com/nhooey).

**Example**:

```nix
mkCljsApp {
  projectSrc = ./.;
  name = "me.lafuente/my-app";
  version = "1.0.0";
}
```

**Example**, with npm dependencies:

```nix
# package.json and package-lock.json are in the project root
mkCljsApp {
  projectSrc = ./.;
  name = "me.lafuente/my-app";
  npmRoot = ./.;
}
```

**Example**, with shadow-cljs in an alias and the output in
`resources/public`:

```nix
# deps.edn:
#   {:paths ["src"]
#    :deps {org.clojure/clojurescript {:mvn/version "..."}}
#    :aliases {:shadow-cljs
#              {:extra-deps {thheller/shadow-cljs {:mvn/version "..."}}
#               :main-opts ["-m" "shadow.cljs.devtools.cli"]}}}
mkCljsApp {
  projectSrc = ./.;
  name = "me.lafuente/my-app";
  aliases = [ "shadow-cljs" ];
  installPaths = [ "resources/public" ];
}
```

### mkBabashka

Builds [Babashka](https://github.com/babashka/babashka/) with the specified
features. See
[babashka feature flags](https://github.com/babashka/babashka/blob/7b10adc69ac9f64811296038bf01b577dc79fe58/doc/build.md#feature-flags)
for the full list. Notice that the feature names in the Nix wrapper are case
insensitive and we can omit the `BABASHKA_FEATURE_` prefix.

Takes the following attributes:

- **withFeatures**: List of extra Babashka features. (Default: `[]`)

- **bbLean**: Disable default Babashka features. (Default: `false`)

- **graalvm**: GraalVM used at build time. (Default: `nixpkgs.graalvmPackages.graalvm-ce`)

- **wrap**: Create a wrapper with `rlwrap` (Default: `true`)

**Example**:

```nix
mkBabashka {
  withFeatures = [ "jdbc" "sqlite" ];
}
```

## Helpers

- [mkCljCli](#mkcljcli): Takes a derivation created with `customJdk` and returns
  a valid command to launch the application, as a string. Useful when creating a
  container.
- [bbTasksFromFile](#bbTasksFromFile): Helper to wrap all the clojure functions
  in a file as bash scripts. Useful to create a nix develpment shell with
  [devshell](https://github.com/numtide/devshell)
- [mk-deps-cache](#mk-deps-cache): Creates a Clojure deps cache (maven cache +
  gitlibs cache). Used by `mkCljBin` and `mkCljLib`. You can use this function
  to to have access to the cache in a nix derivation.

### mkCljCli

Returns a list containing the command and arguments to launch an application
created with `customJdk`. This is useful for container configurations where you
need the command as a list rather than a bash script. Takes the following
attributes (those without a default are mandatory):

**jdkDrv**: Derivation generated with `customJdk`

**java-opts**: Extra arguments for the Java command (Default: `[]`)

**extra-args**: Extra arguments for the Clojure application (Default: `[]`)

**Example**:

```nix
mkCljCli {
  jdkDrv = self.packages."${system}".jdk-tuto;
  java-opts = [ "-Dclojure.compiler.direct-linking=true" ];
  extra-args = [ "--foo" "bar" ];
}
```

### bbTasksFromFile

Reads a Clojure file, for each function generates a
[devshell](https://github.com/numtide/devshell) command. Takes a path (to a
Clojure file) or the following attributes:

**file**: Path to the Clojure file

**bb**: Babashka derivation (Default: `nixpkgs.babashka`)

**Example**:

```nix
devShells.default =
  pkgs.devshell.mkShell {
    commands = pkgs.bbTasksFromFile ./tasks.clj;
    # or
    commands = pkgs.bbTasksFromFile {
      file = ./tasks.clj;
      bb = pkgs.mkBabashka { withFeatures = [ "jdbc" "sqlite" ]; };
    };
  }
```

### mk-deps-cache

Generate maven + gitlib cache from a lock file. This is a lower level helper,
usually you want to use `mkCljBin` or `mkCljLib` and define a custom build
command with the `buildCommand` argument.

**lockfile**: deps-lock.json file

**Example**:

```nix
mk-deps-cache {
  lockfile = ./deps-lock.json;
}
```
