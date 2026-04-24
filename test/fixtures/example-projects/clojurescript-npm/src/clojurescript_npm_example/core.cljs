(ns clojurescript-npm-example.core
  (:require ["left-pad" :as left-pad]))

(defn init []
  (js/console.log (left-pad "1" 3 "0")))
