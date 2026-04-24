{
  description = "ClojureScript example pinning the deprecated slash-in-name form";

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
          # Exercises the deprecated slash-in-name overload. Should still
          # build, but emits a lib.warn pointing users to libCoordinate.
          default = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "cljs-legacy-name-example/app";
            version = "0.1.0";
            buildTarget = "browser";
            buildId = "app";
          };
        };
      }
    );
}
