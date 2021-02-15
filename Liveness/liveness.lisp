(in-package #:cleavir-liveness)

(defun computer (association-get association-set
                 inputs outputs predecessors)
  (declare (type (function (t) cleavir-set:set) association-get)
           (type (function (cleavir-set:set t)) association-set)
           (type (function (t) cleavir-set:set) inputs outputs)
           (type (function (t) cleavir-set:set) map-predecessors))
  (labels ((inputs (node) (funcall inputs node))
           (outputs (node) (funcall outputs node))
           (predecessors (node) (funcall predecessors node))
           (live-before (node) (funcall association-get node))
           ((setf live-before) (new-liveness-set node)
             (funcall association-set new-liveness-set node))
           (traverse (node)
             (let ((live-before (live-before node))
                   (inputs (inputs node)))
               (unless (cleavir-set:set<= inputs live-before)
                 (cleavir-set:nunionf (live-before node) inputs)
                 (cleavir-set:doset (p (predecessors node))
                   (cleavir-set:nunionf (live-before p) live-before)
                   (cleavir-set:nsubtractf (live-before p) (outputs p))
                   (traverse p))))))
    #'traverse))

(defun liveness (start-node successors predecessors
                 association-get association-set
                 inputs outputs)
  (cleavir-utilities:map-nodes start-node successors
                               (computer association-get association-set
                                         inputs outputs predecessors)))
