# clj-nix

Nix helpers for Clojure projects

STATUS: alpha.

## Overview

The main goal of the project is to reduce the friction between Clojure and Nix.
Nix is a great tool to build and deploy software, but Clojure is not well
supported in the Nix ecosystem.

`clj-nix` tries to improve the situation, providing Nix helpers to interact with
Clojure projects, including ClojureScript applications via `mkCljsApp` (compiled
with shadow-cljs for Node.js and browser targets)

Full documentation: https://jlesquembre.github.io/clj-nix/
