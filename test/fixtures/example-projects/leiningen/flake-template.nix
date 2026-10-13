# vi: ft=nix
# Local Variables:
# mode: nix
# End:
{
  description = "A clj-nix flake";

  inputs = {
    clj-nix.url = "{{cljnixUrl}}";
    # clj-nix's locked nixpkgs, so every run builds the same derivations
    nixpkgs.follows = "clj-nix/nixpkgs";
  };
  outputs =
    {
      self,
      nixpkgs,
      clj-nix,
    }:

    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      packages = nixpkgs.lib.genAttrs supportedSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ clj-nix.overlays.default ];
          };
        in
        {
          mkCljBin-test = pkgs.mkCljBin {
            projectSrc = ./.;
            name = "me.lafuente/cljdemo";
            main-ns = "leiningen-example-project.core";
            jdkRunner = pkgs.jdk_headless;
            enableLeiningen = true;
            buildCommand = "lein uberjar";
          };

          mkCljBin-test-with-tests = pkgs.mkCljBin {
            projectSrc = ./.;
            name = "me.lafuente/cljdemo";
            main-ns = "leiningen-example-project.core";
            jdkRunner = pkgs.jdk_headless;
            enableLeiningen = true;
            buildCommand = "lein uberjar";
            doCheck = true;
            checkPhase = "lein test";
          };
        }
      );
    };
}
