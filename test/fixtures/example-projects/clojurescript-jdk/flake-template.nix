{
  description = "ClojureScript example project with a pinned JDK";

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
    in
    {
      packages = forAllSystems perSystem;
    };
}
