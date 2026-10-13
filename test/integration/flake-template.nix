# vi: ft=nix
{
  description = "A clj-nix flake";

  inputs = {
    clj-nix.url = "{{cljnixUrl}}";
    # clj-nix's locked nixpkgs, so every run builds the same derivations
    nixpkgs.follows = "clj-nix/nixpkgs";
  };
  outputs = { self, nixpkgs, clj-nix }:

    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      # The derivations the tests build, for the given package set
      testDrvs = pkgs:
        let
          cljpkgs = clj-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
        in
        rec {
          mkCljBin-test = cljpkgs.mkCljBin {
            projectSrc = ./.;
            name = "me.lafuente/cljdemo";
            main-ns = "hello.core";
            jdkRunner = pkgs.jdk17_headless;
          };

          customJdk-test = cljpkgs.customJdk {
            cljDrv = mkCljBin-test;
            locales = "en,es";
          };

          mkGraalBin-test = cljpkgs.mkGraalBin {
            cljDrv = mkCljBin-test;
            graalvmXmx = "-J-Xmx5g";
            meta.description = "mkGraalBin test";
          };
        };
    in
    {
      packages = nixpkgs.lib.genAttrs supportedSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cljpkgs = clj-nix.legacyPackages.${system};

          # Container images run on Linux, so on macOS build them and their
          # contents for Linux on the same CPU (this needs a Linux builder).
          # On Linux, pkgsLinux is pkgs itself.
          linuxPkgs = pkgs.pkgsLinux;
          linuxDrvs = testDrvs linuxPkgs;
        in
        testDrvs pkgs // {
          jvm-container-test =
            linuxPkgs.dockerTools.buildLayeredImage {
              name = "jvm-container-test";
              tag = "latest";
              config = {
                Cmd = clj-nix.lib.mkCljCli { jdkDrv = linuxDrvs.customJdk-test; };
              };
            };

          graal-container-test =
            let
              graalDrv = linuxDrvs.mkGraalBin-test;
            in
            linuxPkgs.dockerTools.buildLayeredImage {
              name = "graal-container-test";
              tag = "latest";
              config = {
                Cmd = [ "${graalDrv}/bin/${graalDrv.pname}" ];
              };
            };

          babashka-test = cljpkgs.mkBabashka { };

          babashka-with-features-test = cljpkgs.mkBabashka {
            withFeatures = [ "jdbc" "sqlite" ];
          };

        });
    };

}
