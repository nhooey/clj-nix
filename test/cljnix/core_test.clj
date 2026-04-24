(ns cljnix.core-test
  (:require
    [clojure.test :refer [deftest is use-fixtures testing]]
    [babashka.fs :as fs]
    [clojure.string :as string]
    [cljnix.test-helpers :as h]
    [cljnix.core :as c]
    [clojure.tools.deps.specs :as deps.spec]
    [clojure.tools.deps.util.maven :as mvn]
    [clojure.spec.alpha :as s]
    [matcher-combinators.test]
    [matcher-combinators.matchers :as m]))

(def all-deps '{:deps {org.clojure/clojure {:mvn/version "1.11.1"}
                       clj-kondo/clj-kondo {:mvn/version "2022.04.26-20220502.201054-5"}
                       cider/piggieback    {:mvn/version "0.4.1-SNAPSHOT"}
                       io.github.clojure/tools.build {:git/tag "v0.10.13"
                                                      :git/sha "ae52edfedef4ca72e699e9c86abfe0940e97dc26"}
                       dev.weavejester/medley {:mvn/version "1.10.0"}
                       cheshire/cheshire {:mvn/version "5.10.2"}}})

(defn- dissoc-dep
  [m dep]
  (update m :deps #(dissoc % dep)))

(defn- maven-deps
  [deps-map]
  (c/maven-deps
    (h/basis deps-map)
    mvn/standard-repos))

(use-fixtures :once (h/deps-cache-fixture all-deps))

(defn- missing-git-deps
  [deps deps-in-cache]
  {:pre [(s/valid? ::deps.spec/deps-map deps)
         (s/valid? ::deps.spec/deps-map deps-in-cache)]}
  (fs/with-temp-dir [cache-dir {:prefix "gitdeps_cache"}]
    (let [git-deps (c/git-deps (h/basis deps))]
      (c/make-git-cache! (c/git-deps (h/basis deps-in-cache))
                         cache-dir)
      (c/missing-git-deps git-deps cache-dir))))


(deftest missing-git-deps-test
  (testing "git cache is empty"
    (is (= []
           (fs/with-temp-dir [cache-dir {:prefix "gitdeps_cache"}]
             (c/missing-git-deps (c/git-deps (h/basis all-deps))
                                 cache-dir)))))

  (testing "No missing git deps"
    (is (= []
           (missing-git-deps all-deps all-deps))))

  (testing "Some missing git deps"
    (is (match? [{:lib 'io.github.clojure/tools.build,
                  :rev "ae52edfedef4ca72e699e9c86abfe0940e97dc26"}]
                (missing-git-deps
                  (dissoc-dep all-deps 'io.github.clojure/tools.build)
                  all-deps))))

  (testing "Should get all deps"
    (is (match? [{:lib 'io.github.clojure/tools.build,
                  :rev "ae52edfedef4ca72e699e9c86abfe0940e97dc26"}]
                (missing-git-deps
                  {}
                  all-deps)))))


(deftest all-aliases-combinations
  (let [aliases-combinations #'c/aliases-combinations]
    (is (= [["deps.edn" nil]]
           (aliases-combinations ["deps.edn" nil])))

    (is (match? (m/in-any-order
                  [["deps.edn" nil]
                   ["deps.edn" :test]])
                (aliases-combinations ["deps.edn" [:test]])))

    (is (match? (m/in-any-order
                  [["deps.edn" nil]
                   ["deps.edn" :test]
                   ["deps.edn" :build]])
                (aliases-combinations ["deps.edn" [:test :build]])))

    (is (match? (m/in-any-order
                  [["deps.edn" nil]
                   ["deps.edn" :build]
                   ["deps.edn" :test]
                   ["deps.edn" :foo]])
                (aliases-combinations ["deps.edn" [:test :build :foo]])))))

(deftest maven-deps-test
  (testing "Specific SNAPSHOT timestamp version"
    (let [mvn-deps (maven-deps {:deps {'cider/piggieback {:mvn/version "0.4.1-20190222.154954-1"}}})]
      (is (match?
            {:hash "sha256-PvlYv5KwGYHd1MCIQiMNRoVAJRmWLF7FuEM9OMh0FOk=",
             :lib 'cider/piggieback,
             :mvn-path "cider/piggieback/0.4.1-SNAPSHOT/piggieback-0.4.1-20190222.154954-1.jar",
             :mvn-repo "https://repo.clojars.org/",
             :snapshot "piggieback-0.4.1-SNAPSHOT.jar",}
            (h/find-dep 'cider/piggieback mvn-deps)))
      (is (match?
            (m/embeds [{:hash "sha256-PvlYv5KwGYHd1MCIQiMNRoVAJRmWLF7FuEM9OMh0FOk=",
                        :lib 'cider/piggieback,
                        :mvn-path "cider/piggieback/0.4.1-SNAPSHOT/piggieback-0.4.1-20190222.154954-1.jar",
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "piggieback-0.4.1-SNAPSHOT.jar",}
                       {:hash "sha256-rEsytjVma2/KsuMh2s/dPJzhDJ8XqLkaQmIUFEnWIjU=",
                        :mvn-path "cider/piggieback/0.4.1-SNAPSHOT/piggieback-0.4.1-20190222.154954-1.pom",
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "piggieback-0.4.1-SNAPSHOT.pom",}])
            mvn-deps))))

  (testing "SNAPSHOT version resolves to latest timestamp"
    (let [mvn-deps (maven-deps {:deps {'cider/piggieback {:mvn/version "0.4.1-SNAPSHOT"}}})]
      (is (match?
            {:hash "sha256-PvlYv5KwGYHd1MCIQiMNRoVAJRmWLF7FuEM9OMh0FOk=",
             :lib 'cider/piggieback,
             :mvn-path "cider/piggieback/0.4.1-SNAPSHOT/piggieback-0.4.1-20190222.154954-1.jar",
             :mvn-repo "https://repo.clojars.org/",
             :snapshot "piggieback-0.4.1-SNAPSHOT.jar",}
            (h/find-dep 'cider/piggieback mvn-deps)))
      (is (match?
            (m/embeds [{:hash "sha256-PvlYv5KwGYHd1MCIQiMNRoVAJRmWLF7FuEM9OMh0FOk=",
                        :lib 'cider/piggieback,
                        :mvn-path "cider/piggieback/0.4.1-SNAPSHOT/piggieback-0.4.1-20190222.154954-1.jar",
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "piggieback-0.4.1-SNAPSHOT.jar",}
                       {:hash "sha256-rEsytjVma2/KsuMh2s/dPJzhDJ8XqLkaQmIUFEnWIjU=",
                        :mvn-path "cider/piggieback/0.4.1-SNAPSHOT/piggieback-0.4.1-20190222.154954-1.pom",
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "piggieback-0.4.1-SNAPSHOT.pom",}])
            mvn-deps))))


  (testing "Latest SNAPSHOT version is used"
    (let [mvn-deps (maven-deps {:deps {'clj-kondo/clj-kondo {:mvn/version "2022.04.26-SNAPSHOT"}}})
          snapshot-resolved-version "2022.04.26-20220526.212013-27"]
      (is (match?
            {:mvn-path (str "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-" snapshot-resolved-version ".jar",)
             :mvn-repo "https://repo.clojars.org/",
             :snapshot "clj-kondo-2022.04.26-SNAPSHOT.jar",}
            (h/find-dep 'clj-kondo/clj-kondo mvn-deps)))
      (is (match?
            {:mvn-path (str "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-" snapshot-resolved-version ".pom")
             :mvn-repo "https://repo.clojars.org/",
             :snapshot "clj-kondo-2022.04.26-SNAPSHOT.pom",}
            (h/find-pom "clj-kondo/clj-kondo" mvn-deps)))
      (is (match?
            (m/embeds [{:mvn-path (str "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-" snapshot-resolved-version ".jar",)
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "clj-kondo-2022.04.26-SNAPSHOT.jar",}
                       {:mvn-path (str "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-" snapshot-resolved-version ".pom")
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "clj-kondo-2022.04.26-SNAPSHOT.pom"}])
            mvn-deps))))

  (testing "Exact SNAPSHOT version is used"
    (let [mvn-deps (maven-deps {:deps {'clj-kondo/clj-kondo {:mvn/version "2022.04.26-20220502.201054-5"}}})]
      (is (match?
            {:mvn-path "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-2022.04.26-20220502.201054-5.jar",
             :mvn-repo "https://repo.clojars.org/",
             :version "2022.04.26-20220502.201054-5"
             :snapshot "clj-kondo-2022.04.26-SNAPSHOT.jar",}
            (h/find-dep 'clj-kondo/clj-kondo mvn-deps)))
      (is (match?
            {:mvn-path "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-2022.04.26-20220502.201054-5.pom",
             :mvn-repo "https://repo.clojars.org/",
             :snapshot "clj-kondo-2022.04.26-SNAPSHOT.pom",}
            (h/find-pom "clj-kondo/clj-kondo" mvn-deps)))
      (is (match?
            (m/embeds [{:mvn-path "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-2022.04.26-20220502.201054-5.jar",
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "clj-kondo-2022.04.26-SNAPSHOT.jar",}
                       {:mvn-path "clj-kondo/clj-kondo/2022.04.26-SNAPSHOT/clj-kondo-2022.04.26-20220502.201054-5.pom",
                        :mvn-repo "https://repo.clojars.org/",
                        :snapshot "clj-kondo-2022.04.26-SNAPSHOT.pom"}])
            mvn-deps)))))

(deftest ^:network expand-sha-tests
  (fs/with-temp-dir [project-dir {:prefix "dummy_project"}]
    (let [spit-helper (h/make-spit-helper project-dir)]
      (spit-helper "deps.edn" {:deps {'io.github.babashka/fs
                                      {:git/tag "v0.1.6"
                                       :git/sha "31f8b93"}}})
      (is (= [{:lib "io.github.babashka/fs",
                :url "https://github.com/babashka/fs.git",
                :rev "31f8b93638530f8ea7148c22b008ce1d0ccd4b87",
                :tag "v0.1.6"
                :git-dir "https/github.com/babashka/fs",
                :hash "sha256-rlC+1cPnDYNP4UznIWH9MC2xSVQn/XbvKE10tbcsNNI="}]
             (:git-deps (c/lock-file project-dir))))

      (spit-helper "deps.edn" {:deps {'io.github.cognitect-labs/test-runner  {:git/tag "v0.5.0",
                                                                              :git/sha "b3fd0d2"}}})
      (is (= [{:git-dir "https/github.com/cognitect-labs/test-runner",
                :hash "sha256-NZ9/S82Ae1aq0gnuTLOYg/cc7NcYIoK2JP6c/xI+xJE=",
                :lib "io.github.cognitect-labs/test-runner",
                :rev "48c3c67f98362ba1e20526db4eeb6996209c050a",
                :tag "v0.5.0",
                :url "https://github.com/cognitect-labs/test-runner.git"}]
             (:git-deps (c/lock-file project-dir))))

      (spit-helper "deps.edn" {:deps {'io.github.cognitect-labs/test-runner {:git/tag "v0.5.0",
                                                                             :git/sha "b3fd0d2"}}
                               :aliases
                               {:foo
                                {:extra-deps
                                 {'io.github.cognitect-labs/test-runner {:git/sha "48c3c67f98362ba1e20526db4eeb6996209c050a"}}}}})

      (is (= [{:git-dir "https/github.com/cognitect-labs/test-runner",
                :hash "sha256-NZ9/S82Ae1aq0gnuTLOYg/cc7NcYIoK2JP6c/xI+xJE=",
                :lib "io.github.cognitect-labs/test-runner",
                :rev "48c3c67f98362ba1e20526db4eeb6996209c050a",
                :tag "v0.5.0",
                :url "https://github.com/cognitect-labs/test-runner.git"}]
             (:git-deps (c/lock-file project-dir)))))))
