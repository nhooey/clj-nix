{
  description = "ClojureScript example project with a custom installPaths layout";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cljnix = {
      url = "{{cljnixUrl}}";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, cljnix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ cljnix.overlays.default ];
        };
      in
      {
        packages = {
          default = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "app";
            libCoordinate = "cljs-install-paths-example/app";
            version = "0.1.0";
            buildTarget = "browser";
            buildId = "app";
            installPaths = [ "resources/public" ];
            # Also exercise installCommand — drop a marker file so the e2e
            # test can confirm the post-copy hook ran.
            installCommand = ''
              echo "installCommand-ran" > "$out/install-marker.txt"
            '';
          };
        };
      }
    );
}
