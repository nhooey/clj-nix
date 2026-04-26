# vi: ft=nix
# Local Variables:
# mode: nix
# End:
{
  description = "A clj-nix flake";

  inputs = {
    clj-nix.url = "{{cljnixUrl}}";
    nixpkgs.follows = "clj-nix/nixpkgs";
  };

  outputs = { self, nixpkgs, clj-nix }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      perSystem = system:
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
            main-ns = "hello.core";
            jdkRunner = pkgs.jdk_headless;
            enableLeiningen = true;
            buildCommand = "lein uberjar";
          };

          mkCljBin-test-with-tests = pkgs.mkCljBin {
            projectSrc = ./.;
            name = "me.lafuente/cljdemo";
            main-ns = "hello.core";
            jdkRunner = pkgs.jdk_headless;
            enableLeiningen = true;
            buildCommand = "lein uberjar";
            doCheck = true;
            checkPhase = "lein test";
          };
        };
    in
    {
      packages = forAllSystems perSystem;
    };
}
