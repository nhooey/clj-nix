{ stdenv
, lib
, clojure

  # Default JDK.
  # Needed by clj tools.build to compile the code
, jdk

  # Custom utils
, clj-builder
, mk-deps-cache
, fake-git
}:

{
  # User options
  jdkRunner ? jdk # JDK used to build the library
, projectSrc
, name
, version ? "DEV"
, buildCommand ? null
, maven-extra ? [ ]
, ...
}@attrs:

let

  extra-attrs = builtins.removeAttrs attrs [
    "jdkRunner"
    "projectSrc"
    "name"
    "version"
    "buildCommand"
    "maven-extra"
    "nativeBuildInputs"
  ];

  deps-cache = mk-deps-cache {
    lockfile = (projectSrc + "/deps-lock.json");
    inherit maven-extra;
  };

  builder = clj-builder.override { jdk = jdkRunner; };

  fullId = if (lib.strings.hasInfix "/" name) then name else "${name}/${name}";
  groupId = builtins.head (lib.strings.splitString "/" fullId);
  artifactId = builtins.elemAt (lib.strings.splitString "/" fullId) 1;

in
stdenv.mkDerivation ({
  inherit version;

  pname = lib.strings.sanitizeDerivationName artifactId;
  src = projectSrc;

  # Build time deps
  nativeBuildInputs =
    attrs.nativeBuildInputs or [ ]
      ++
      [
        fake-git
        jdkRunner
        (clojure.override { jdk = jdkRunner; })
      ];

  passthru = {
    inherit deps-cache fullId groupId artifactId;
  };

  patchPhase =
    ''
      runHook prePatch
      ${builder}/bin/clj-builder patch-git-sha "$(pwd)"
      runHook postPatch
    '';

  buildPhase =
    ''
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
    +
    (
      if builtins.isNull buildCommand then
        ''
          ${builder}/bin/clj-builder jar "${fullId}" "${version}"
        ''
      else
        ''
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

      # Sort, because `find` lists files in directory order, which differs
      # between filesystems.
      jarPath="$(find target -type f -name "*.jar" -print | sort | head -n 1)"
      cp $jarPath $out

      runHook postInstall
    '';
} // extra-attrs)
