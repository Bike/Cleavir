(cl:in-package #:asdf-user)

(defsystem :cleavir-cst
  :serial t
  :components
  ((:file "packages")
   (:file "concrete-syntax-tree")))
