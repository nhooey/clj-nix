{
  description = "ClojureScript example project with npm deps for testing";

  inputs = {
    cljnix.url = "{{cljnixUrl}}";
    nixpkgs.follows = "cljnix/nixpkgs";
  };

  outputs = { self, nixpkgs, cljnix }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      perSystem = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ cljnix.overlays.default ];
          };
        in
        {
          default = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "app";
            libCoordinate = "cljs-npm-example/app";
            version = "0.1.0";
            buildTarget = "browser";
            buildId = "app";
            npmRoot = ./.;
          };
        };
    in
    {
      packages = forAllSystems perSystem;
    };
}
