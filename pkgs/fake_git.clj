(ns fake-git
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [babashka.fs :as fs]
            [babashka.cli :as cli]))

(defn rev-data [git-dir]
  (if (and git-dir (fs/exists? (str git-dir "/revs")))
    (->> (fs/glob (str git-dir "/revs") "*")
         (mapv #(json/parse-string
                 (slurp (str %))
                 true)))
    []))

(defn result [args]
  (let [git-dir (or (-> args :opts :git-dir)
                    (-> args :opts :C))
        rest-args (:args args)]
    (cond
      (= (first rest-args) "clone")
      ;; Just succeed - don't actually create anything
      {:exit 0}

      (= (first rest-args) "fetch") {:exit 0}

      (= (first rest-args) "worktree")
      ;; git worktree add creates a working directory from the bare repo
      ;; In our case, the "repo" already exists in gitlibs libs cache, so just succeed
      {:exit 0}

      (= rest-args ["tag" "--sort=v:refname"])
      {:exit 0
       :out
       (->> (rev-data git-dir)
            (eduction
             (map :tag)
             (map str/trim)
             (remove str/blank?)
             (remove nil?))
            vec)}

      (= (first rest-args) "rev-parse")
      (let [commit (str/replace (second rest-args) #"\^\{commit\}" "")
            result (->> (rev-data git-dir)
                        (eduction
                         (filter #(or (let [tag (:tag %)]
                                        (and tag (= tag commit)))
                                      (str/starts-with? (:rev %) commit)))
                         (map :rev)
                         (take 1))
                        vec)]
        (if (seq result)
          {:exit 0 :out result}
          ;; For unknown commits, return a synthetic SHA to allow tests to proceed
          ;; This handles test fixtures that reference git deps not in the lock file
          {:exit 0 :out [(str commit (apply str (repeat (- 40 (count commit)) "0")))]}))

      (and (= (first rest-args) "merge-base")
           (= (second rest-args) "--is-ancestor"))
      (let [rev (nth rest-args 2)
            ancestor (nth rest-args 3)
            rev-f (str git-dir "/revs/" rev)
            rev-d (json/parse-string (slurp rev-f))]
        (if (get-in rev-d ["ancestor?" ancestor])
          {:exit 0}
          {:exit 1}))

      :else
      (throw (Exception. (str "fake-git: unknown git command - " args))))))

(defn main* [args]
  (result (cli/parse-args args)))

(defn main []
  (when (= *file* (System/getProperty "babashka.file"))
    (let [{:keys [exit out err] :as res} (main* *command-line-args*)]
      (when err
        (binding [*out* *err*]
          (->> err (str/join "\n") println)))
      (when (= 0 exit)
        (if (seq out)
          (->> out (str/join "\n") println)
          (println "")))  ; Print empty line if no output
      (when (not= 0 exit)
        (System/exit exit)))))
(main)
