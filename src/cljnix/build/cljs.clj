(ns cljnix.build.cljs
  "ClojureScript build implementation using shadow-cljs.

  This namespace provides ClojureScript compilation support, implementing
  the Builder protocol from cljnix.build.core."
  (:require
    [clojure.java.io :as io]
    [clojure.java.shell :as sh]
    [clojure.string :as string]
    [clojure.tools.deps :as deps]
    [cljnix.build.core :as build-core]))

;; ClojureScript-specific constants

(def default-output-dir "target/cljs")
(def default-build-id :app)

;; Helper functions

(defn- get-paths
  "Get paths from deps.edn file"
  [deps-file]
  (-> deps-file
      io/file
      deps/slurp-deps
      :paths
      (or ["src"])))

(defn- find-shadow-config
  "Find shadow-cljs.edn configuration file in project directory."
  [project-dir]
  (let [config-path (io/file project-dir "shadow-cljs.edn")]
    (when (.exists config-path)
      (str config-path))))

(defn- alias-flag
  "Build the `-M[:alias1:alias2]` flag for clojure CLI given a seq of alias strings."
  [aliases]
  (if (seq aliases)
    (str "-M:" (string/join ":" (map name aliases)))
    "-M"))

(defn- run-shadow-cljs
  "Execute shadow-cljs via the clojure CLI.

  Two invocation shapes, matching how real projects wire up shadow-cljs:

  * No aliases (shadow-cljs is a top-level :deps entry):
        clojure -M -m shadow.cljs.devtools.cli <command> <args...>

  * With aliases (shadow-cljs lives under a deps.edn alias whose
    :main-opts already include `-m shadow.cljs.devtools.cli`, e.g.
        :shadow-cljs {:extra-deps {thheller/shadow-cljs ...}
                      :main-opts  [\"-m\" \"shadow.cljs.devtools.cli\"]}):
        clojure -M:alias1:alias2 <command> <args...>
    The alias's :main-opts supplies -m, so we must NOT pass -m again —
    shadow-cljs would see it as a positional arg and reject it.

  Returns {:exit exit-code :out stdout :err stderr}"
  [command aliases & args]
  (let [base [(alias-flag aliases)]
        main-opts (if (seq aliases)
                    [command]
                    ["-m" "shadow.cljs.devtools.cli" command])
        cmd-args (into ["clojure"] (concat base main-opts args))
        result (apply sh/sh cmd-args)]
    result))

;; Public ClojureScript build functions

(defn compile-cljs
  "Compile ClojureScript using shadow-cljs.

  Required opts:
  - :lib-name - Library name
  - :version - Version string
  - :build-id - Shadow-cljs build ID (default: :app)

  Optional opts:
  - :target - Build target: :browser or :node-script (default: :browser)
  - :output-dir - Output directory (default: target/cljs)
  - :optimizations - Optimization level: :none, :simple, :advanced (default: :advanced)
  - :aliases - deps.edn aliases to activate (default: []). Most shadow-cljs
               projects put thheller/shadow-cljs under an alias like
               :shadow-cljs or :dev. Supply those names here so the default
               build command becomes `clojure -M:alias1:alias2 -m ...`."
  [{:keys [lib-name version build-id target output-dir optimizations aliases]
    :or {build-id default-build-id
         target :browser
         output-dir default-output-dir
         optimizations :advanced
         aliases []}
    :as opts}]
  (build-core/validate-build-opts opts [:lib-name :version])

  (let [lib-name (build-core/normalize-lib-name lib-name)
        build-id-str (name build-id)]

    (println (format "Compiling ClojureScript: %s %s (build: %s, target: %s, aliases: %s)"
                     lib-name version build-id-str (name target)
                     (if (seq aliases) (pr-str (vec aliases)) "none")))

    ;; Run shadow-cljs release build. Stream stdout/stderr so warnings and
    ;; "no sources found" style failures don't get swallowed on exit 0.
    (let [result (run-shadow-cljs "release" aliases build-id-str)]
      (when-let [out (not-empty (:out result))] (print out) (flush))
      (when-let [err (not-empty (:err result))] (binding [*out* *err*] (print err) (flush)))
      (when-not (zero? (:exit result))
        (throw (ex-info "ClojureScript compilation failed"
                        {:exit (:exit result)
                         :stderr (:err result)
                         :stdout (:out result)})))

      (println "ClojureScript compilation successful")
      {:output-dir output-dir
       :build-id build-id
       :target target
       :lib-name lib-name
       :aliases (vec aliases)})))

(defn package-cljs
  "Package compiled ClojureScript output.

  For browser builds: Creates a directory with HTML, JS, and assets
  For Node.js builds: Creates a directory with the main JS file

  Required opts:
  - :lib-name - Library name
  - :version - Version string
  - :build-id - Shadow-cljs build ID
  - :target - Build target (:browser or :node-script)

  Optional opts:
  - :output-dir - Source directory for compiled output
  - :package-dir - Destination directory (default: target/package)"
  [{:keys [lib-name version build-id target output-dir package-dir]
    :or {output-dir default-output-dir
         package-dir "target/package"}
    :as opts}]
  (build-core/validate-build-opts opts [:lib-name :version :build-id :target])

  (let [lib-name (build-core/normalize-lib-name lib-name)
        source-dir (io/file output-dir (name build-id))
        dest-dir (io/file package-dir)]

    (println (format "Packaging ClojureScript: %s %s" lib-name version))

    ;; Create destination directory
    (.mkdirs dest-dir)

    ;; Copy compiled output
    (if (.exists source-dir)
      (do
        (sh/sh "cp" "-r" (str source-dir) (str dest-dir))
        (println (format "Packaged to: %s" package-dir))
        {:package-dir package-dir
         :lib-name lib-name
         :version version})
      (throw (ex-info "Compiled output not found"
                      {:source-dir (str source-dir)
                       :build-id build-id})))))

(defn build-jar
  "Build a JAR containing ClojureScript source files (not compiled output).

  This creates a library JAR with .cljs source files for use as a dependency.
  For compiled JavaScript output, use compile-cljs and package-cljs instead."
  [{:keys [version] :as opts}]
  (build-core/validate-build-opts opts [:lib-name :version])

  (let [lib-name (build-core/normalize-lib-name (:lib-name opts))
        src-dirs (get-paths "deps.edn")
        output-jar (build-core/output-jar-path lib-name version)]

    (println (format "Building ClojureScript source JAR: %s" output-jar))

    ;; Create a simple JAR with source files
    ;; For production use, consider using tools.build or a similar tool
    (let [jar-cmd ["jar" "cf" output-jar "-C" (first src-dirs) "."]]
      (let [result (apply sh/sh jar-cmd)]
        (when-not (zero? (:exit result))
          (throw (ex-info "JAR creation failed"
                          {:exit (:exit result)
                           :stderr (:err result)})))

        (println (format "Created: %s" output-jar))
        {:output-jar output-jar
         :lib-name lib-name
         :version version}))))

;; Builder protocol implementation for ClojureScript

(defrecord CljsBuilder []
  build-core/Builder

  (build-jar [_this opts]
    (build-jar opts))

  (build-uberjar [_this opts]
    (throw (ex-info "Uberjar not applicable for ClojureScript. Use compile-cljs to create JavaScript bundles."
                    {:lib-name (:lib-name opts)})))

  (get-src-paths [_this project-file]
    (get-paths project-file)))

(defn create-builder
  "Create a ClojureScript builder instance."
  []
  (->CljsBuilder))
