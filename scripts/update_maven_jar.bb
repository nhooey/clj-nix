#!/usr/bin/env bb

;; Bumps a jar pinned in a nix-fetcher-data `srcFromJson` file
;; ({"version", "fetcher": "fetchurl", "args": {"url", "hash"}}) to the newest
;; release in its Maven repository, e.g. Clojars.
;;
;; Usage: bb scripts/update_maven_jar.bb pkgs/graal-build-time.json

(ns update-maven-jar
  (:require [babashka.http-client :as http]
            [babashka.process :refer [shell]]
            [cheshire.core :as json]
            [clojure.string :as str]))

(defn release?
  "Plain numeric versions only: skips -SNAPSHOT, -alpha, -RC1 and the like."
  [version]
  (re-matches #"\d+(\.\d+)*" version))

(defn parse-version
  [version]
  (mapv parse-long (str/split version #"\.")))

(defn latest-release
  [metadata-xml]
  (->> (re-seq #"<version>([^<]+)</version>" metadata-xml)
       (map second)
       (filter release?)
       (sort-by parse-version)
       last))

(defn prefetch-hash
  [url]
  (-> (shell {:out :string}
             "nix" "--extra-experimental-features" "nix-command"
             "store" "prefetch-file" "--json" url)
      :out
      (json/parse-string true)
      :hash))

(defn -main
  [src-file]
  (let [{:keys [version args] :as src} (json/parse-string (slurp src-file) true)
        ;; <repo>/<group path>/<artifact>/<version>/<artifact>-<version>.jar
        [_ artifact-url artifact] (re-matches
                                   (re-pattern (str "(.*/([^/]+))/\\Q" version "\\E/[^/]+\\.jar"))
                                   (:url args))
        _ (when-not artifact-url
            (throw (ex-info "URL is not a Maven jar URL for this version"
                            {:url (:url args) :version version})))
        new-version (latest-release
                     (:body (http/get (str artifact-url "/maven-metadata.xml"))))]
    (if (= version new-version)
      (println (str artifact " is already at the latest release, " version))
      (let [url (str artifact-url "/" new-version "/" artifact "-" new-version ".jar")]
        (println (str "Updating " artifact ": " version " -> " new-version))
        (spit src-file
              (str (json/generate-string
                    (-> src
                        (assoc :version new-version)
                        (assoc-in [:args :url] url)
                        (assoc-in [:args :hash] (prefetch-hash url)))
                    {:pretty true})
                   "\n"))))))

(-main (first *command-line-args*))
