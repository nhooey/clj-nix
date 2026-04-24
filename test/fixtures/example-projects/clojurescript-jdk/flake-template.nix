{
  description = "ClojureScript example project with a pinned JDK";

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
            libCoordinate = "cljs-jdk-example/app";
            version = "0.1.0";
            buildTarget = "browser";
            buildId = "app";
            jdk = pkgs.jdk21;
            # Record java -version so the e2e test can assert which JDK ran.
            postInstall = ''
              java -version 2> "$out/jdk-used.txt"
            '';
          };
        };
      }
    );
}
