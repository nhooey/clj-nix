(ns cljs-example.npm
  (:require ["left-pad" :as left-pad]))

(defn init []
  (js/console.log (left-pad "42" 5 "0")))
