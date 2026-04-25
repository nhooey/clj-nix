{
  description = "ClojureScript example project with a custom installPaths layout";

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
    in
    {
      packages = forAllSystems perSystem;
    };
}
