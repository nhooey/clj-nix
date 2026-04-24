(ns cljnix.nix-test
  (:require
    [clojure.test :refer [deftest is use-fixtures]]
    [babashka.fs :as fs]
    [cljnix.test-helpers :as h]
    [cljnix.nix :as nix]
    [matcher-combinators.test]))

(def all-deps '{:deps {org.clojure/clojure {:mvn/version "1.11.1"}
                       io.github.clojure/tools.build {:git/sha "ae52edfedef4ca72e699e9c86abfe0940e97dc26"
                                                      :git/tag "v0.10.13"}}})

(use-fixtures :once (h/deps-cache-fixture all-deps))

(deftest nix-hash-test
  (is (= "sha256-I4G26UI6tGUVFFWUSQPROlYkPWAGuRlK/Bv0+HEMtN4="
         (nix/nix-hash (fs/expand-home "~/.m2/repository/org/clojure/clojure/1.11.1/clojure-1.11.1.jar"))))

  (is (string? (nix/nix-hash (fs/expand-home "~/.gitlibs/libs/io.github.clojure/tools.build/ae52edfedef4ca72e699e9c86abfe0940e97dc26")))))
