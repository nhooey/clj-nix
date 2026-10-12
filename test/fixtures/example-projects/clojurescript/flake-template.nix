# vi: ft=nix
# Local Variables:
# mode: nix
# End:
{
  description = "A clj-nix ClojureScript flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    clj-nix = {
      url = "{{cljnixUrl}}";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          mkCljsApp-test = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "me.lafuente/cljs-example";
            version = "0.1.0";
          };

          mkCljsApp-test-aliases = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "me.lafuente/cljs-example";
            version = "0.1.0";
            aliases = [ "shadow-cljs" ];
          };

          # A JDK other than nixpkgs' default `jdk` (21). Not an older one:
          # shadow-cljs 3's Closure Compiler needs Java 21 or newer.
          mkCljsApp-test-jdk = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "me.lafuente/cljs-example";
            version = "0.1.0";
            jdkRunner = pkgs.jdk25_headless;
            # Record the JVM the build's `clojure` runs on
            postInstall = ''
              clojure -M -e '(print (System/getProperty "java.specification.version"))' \
                > "$out/java-version.txt"
            '';
          };

          # The `npm` build requires left-pad, from package-lock.json
          mkCljsApp-test-npm = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "me.lafuente/cljs-example";
            version = "0.1.0";
            buildId = "npm";
            npmRoot = ./.;
          };

          mkCljsApp-test-node-modules = pkgs.mkCljsApp {
            projectSrc = ./.;
            name = "me.lafuente/cljs-example";
            version = "0.1.0";
            buildId = "npm";
            nodeModules = pkgs.importNpmLock.buildNodeModules {
              npmRoot = ./.;
              inherit (pkgs) nodejs;
            };
          };
        }
      );
    };
}
