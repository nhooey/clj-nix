{
  description = "A clj-nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    clj-nix.url = "github:jlesquembre/clj-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      clj-nix,
    }:

    # Nixpkgs 26.11 dropped x86_64-darwin; flake-utils.lib.eachDefaultSystem
    # still lists it.
    flake-utils.lib.eachSystem [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ] (system: {

      packages = {

        default = clj-nix.lib.mkCljApp {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            # Option list:
            # https://jlesquembre.github.io/clj-nix/options/
            {
              projectSrc = ./.;
              name = "me.lafuente/cljdemo";
              main-ns = "hello.core";

              nativeImage.enable = true;

              # customJdk.enable = true;
            }
          ];
        };

      };
    });
}
