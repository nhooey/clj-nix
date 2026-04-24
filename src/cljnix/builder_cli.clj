(ns cljnix.builder-cli
  "CLI entry point for build commands.

  This namespace dispatches build commands to appropriate builders.
  Supports JVM and ClojureScript builds."
  (:require
    [cljnix.utils :as utils]
    [cljnix.build :as build]
    [cljnix.build.cljs :as cljs]
    [cljnix.check :as check]
    [clojure.data.json :as json]
    [clojure.string]))

;; Command registry - extensible for additional build types
(def ^:private command-handlers
  "Registry of command handlers. Can be extended for additional build types."
  (atom {}))

(defn register-command!
  "Register a new command handler.

  Usage:
    (register-command! \"custom-build\" my-handler-fn)"
  [command-name handler-fn]
  (swap! command-handlers assoc command-name handler-fn))

;; Helper functions

(defn- check-main-class
  "Check if main-ns has :gen-class (JVM-specific requirement)."
  [args]
  (or
   (check/main-gen-class
    (interleave
     [:lib-name :version :main-ns]
     args))
   (throw (ex-info "main-ns class does not specify :gen-class" {:args args}))))

(defn- str->json
  "Parse JSON string to Clojure data."
  [s]
  (json/read-str s :key-fn keyword))

;; Built-in command handlers

(defn- handle-patch-git-sha
  "Handler for patch-git-sha command."
  [args]
  (apply utils/expand-shas! args))

(defn- handle-jar
  "Handler for jar command (JVM library build)."
  [args]
  (build/jar
    (interleave
      [:lib-name :version]
      args)))

(defn- handle-uber
  "Handler for uber command (JVM uberjar build)."
  [args]
  (check-main-class args)
  (-> (zipmap [:lib-name :version :main-ns :compile-clj-opts :javac-opts :uber-opts] args)
      (update :compile-clj-opts str->json)
      (update :javac-opts str->json)
      (update :uber-opts str->json)
      (build/uber)))

(defn- handle-check-main
  "Handler for check-main command."
  [args]
  (check-main-class args))

(defn- parse-aliases
  "Parse the trailing aliases argument.
  Accepts nil, \"\" (no aliases), or a comma-separated list like \"shadow-cljs,dev\"."
  [s]
  (if (or (nil? s) (= "" s))
    []
    (->> (clojure.string/split s #",")
         (remove clojure.string/blank?)
         (vec))))

(defn- handle-cljs-compile
  "Handler for cljs-compile command (ClojureScript compilation).

  Positional args:
    <lib-name> <version> <build-id> <target> [aliases]

  The optional trailing <aliases> arg is a comma-separated list of
  deps.edn alias names (e.g. \"shadow-cljs,dev\") used to construct the
  `-M:alias1:alias2` flag for the default shadow-cljs command."
  [args]
  (let [[lib-name version build-id target aliases-str] args]
    (-> {:lib-name lib-name
         :version version
         :build-id build-id
         :target target
         :aliases (parse-aliases aliases-str)}
        (update :build-id keyword)
        (update :target keyword)
        (cljs/compile-cljs))))

(defn- handle-cljs-package
  "Handler for cljs-package command (ClojureScript packaging)."
  [args]
  (-> (zipmap [:lib-name :version :build-id :target] args)
      (update :build-id keyword)
      (update :target keyword)
      (cljs/package-cljs)))

;; Register built-in commands
(register-command! "patch-git-sha" handle-patch-git-sha)
(register-command! "jar" handle-jar)
(register-command! "uber" handle-uber)
(register-command! "check-main" handle-check-main)
(register-command! "cljs-compile" handle-cljs-compile)
(register-command! "cljs-package" handle-cljs-package)

;; Main CLI entry point

(defn -main
  "Main CLI entry point. Dispatches to appropriate command handler.

  Usage:
    clj-builder <command> <args...>

  JVM Commands:
    jar <lib-name> <version>     - Build a library JAR
    uber <lib-name> <version> <main-ns> <compile-opts> <javac-opts> <uber-opts> - Build uberjar
    check-main <lib-name> <version> <main-ns> - Check if main-ns has :gen-class

  ClojureScript Commands:
    cljs-compile <lib-name> <version> <build-id> <target> [aliases] - Compile ClojureScript
                                                                      (aliases is a comma-separated list, e.g. shadow-cljs,dev)
    cljs-package <lib-name> <version> <build-id> <target>           - Package ClojureScript output

  Utility Commands:
    patch-git-sha <project-dir>  - Expand partial git SHAs to full SHAs

  Additional commands can be registered using register-command!"

  [& [cmd & args]]
  (if-let [handler (get @command-handlers cmd)]
    (handler args)
    (throw (ex-info (str "Unknown command: " cmd)
                    {:command cmd
                     :available-commands (keys @command-handlers)})))
  (shutdown-agents))
