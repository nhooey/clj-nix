# vi: ft=nix
{
  description = "A clj-nix flake";

  inputs = {
    clj-nix.url = "{{cljnixUrl}}";
    # Pin the dummy project to clj-nix's pinned nixpkgs so derivations
    # like `babashka-test = mkBabashka {}` produce store hashes
    # identical to clj-nix's own `babashka` package — Garnix's CI
    # cache hits on them rather than triggering a fresh GraalVM
    # native-image rebuild in a memory-constrained action runner.
    nixpkgs.follows = "clj-nix/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils, clj-nix }:

    flake-utils.lib.eachDefaultSystem (system:
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
        packages = {

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

          babashka-test = cljpkgs.mkBabashka { };

          babashka-with-features-test = cljpkgs.mkBabashka {
            withFeatures = [ "jdbc" "sqlite" ];
          };


        };
      });

}
