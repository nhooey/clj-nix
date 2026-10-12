{
  stdenv,
  lib,
  clojure,

  # Default JDK.
  # Needed by clj tools.build to compile the code
  jdk,

  # Custom utils
  clj-builder,
  mk-deps-cache,
}:

{
  # User options
  jdkRunner ? jdk, # JDK used to build the library
  projectSrc,
  name,
  version ? "DEV",
  buildCommand ? null,
  maven-extra ? [ ],
  ...
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
stdenv.mkDerivation (
  {
    inherit version;

    pname = lib.strings.sanitizeDerivationName artifactId;
    src = projectSrc;

    # Build time deps
    nativeBuildInputs = attrs.nativeBuildInputs or [ ] ++ [
      jdkRunner
      (clojure.override { jdk = jdkRunner; })
    ];

    passthru = {
      inherit
        deps-cache
        fullId
        groupId
        artifactId
        ;
    };

    patchPhase = ''
      runHook prePatch
      ${builder}/bin/clj-builder patch-git-sha "$(pwd)"
      runHook postPatch
    '';

    buildPhase = ''
      runHook preBuild

      export HOME="${deps-cache}"
      export JAVA_TOOL_OPTIONS="-Duser.home=${deps-cache}"
    ''
    + (
      if builtins.isNull buildCommand then
        ''
          ${builder}/bin/clj-builder jar "${fullId}" "${version}"
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

      jarPath="$(find target -type f -name "*.jar" -print | head -n 1)"
      cp $jarPath $out

      runHook postInstall
    '';
  }
  // extra-attrs
)
