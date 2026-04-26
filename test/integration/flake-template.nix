# vi: ft=nix
{
  description = "A clj-nix flake";

  inputs = {
    clj-nix.url = "{{cljnixUrl}}";
    # Pin the dummy project to clj-nix's pinned nixpkgs so derivations
    # built here align with clj-nix's flake outputs.
    nixpkgs.follows = "clj-nix/nixpkgs";
    # NB: no flake-utils input on purpose. `flake-utils.url =
    # "github:numtide/flake-utils"` (no rev) makes `nix flake lock`
    # call api.github.com to resolve HEAD, which gets rate-limited
    # on Garnix's shared runner IP. Inline the only function we
    # used (`eachDefaultSystem`) instead, eliminating the API
    # dependency entirely.
  };
  outputs = { self, nixpkgs, clj-nix }:

    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      perSystem = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cljpkgs = clj-nix.legacyPackages."${system}";

          # Detect if we're on macOS and need to use Linux packages for containers
          isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
          linuxSystem = if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64-linux" else "x86_64-linux";

          # Use native Linux packages for containers (requires remote builders on macOS)
          containerPkgs = if isDarwin then nixpkgs.legacyPackages.${linuxSystem} else pkgs;
          containerCljpkgs = if isDarwin then clj-nix.legacyPackages.${linuxSystem} else cljpkgs;

          # Common function to build a Clojure binary (reusable for containers)
          mkCljBinFor = pkgsSet: cljpkgsSet:
            cljpkgsSet.mkCljBin {
              projectSrc = ./.;
              name = "me.lafuente/cljdemo";
              main-ns = "hello.core";
              jdkRunner = pkgsSet.jdk17_headless;
            };

          # Container-specific builds (Linux on macOS, native on Linux)
          containerCljBin = mkCljBinFor containerPkgs containerCljpkgs;
          containerCustomJdk = containerCljpkgs.customJdk {
            cljDrv = containerCljBin;
            locales = "en,es";
          };
          containerGraalBin = containerCljpkgs.mkGraalBin {
            cljDrv = containerCljBin;
          };
        in
        {
          mkCljBin-test = mkCljBinFor pkgs cljpkgs;

          customJdk-test = cljpkgs.customJdk {
            cljDrv = self.packages."${system}".mkCljBin-test;
            locales = "en,es";
          };

          mkGraalBin-test = cljpkgs.mkGraalBin {
            cljDrv = self.packages."${system}".mkCljBin-test;
          };

          # Build Linux containers for Docker, even on macOS
          jvm-container-test = containerPkgs.dockerTools.buildLayeredImage {
            name = "jvm-container-test";
            tag = "latest";
            config = {
              Cmd = clj-nix.lib.mkCljCli { jdkDrv = containerCustomJdk; };
            };
          };

          graal-container-test = containerPkgs.dockerTools.buildLayeredImage {
            name = "graal-container-test";
            tag = "latest";
            config = {
              Cmd = [ "${containerGraalBin}/bin/${containerGraalBin.pname}" ];
            };
          };

          # Reference clj-nix's prebuilt babashka derivations directly
          # rather than re-invoking mkBabashka here. The local function
          # call evaluates against a slightly different closure than
          # clj-nix's own packages.<system>.babashka and produces a
          # different store hash, causing the Garnix action runner to
          # miss the cache and try to recompile babashka via GraalVM
          # native-image (which OOMs in the runner's ~4.5GB sandbox).
          # Pointing at clj-nix.packages.<system>.* guarantees a hash
          # match against what Garnix already prebuilt.
          babashka-test = clj-nix.packages.${system}.babashka;

          babashka-with-features-test =
            clj-nix.packages.${system}.babashka-with-features;
        };
    in
    {
      packages = forAllSystems perSystem;
    };

}
