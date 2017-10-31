(cl:in-package #:cleavir-partial-inlining)

(defmethod inline-one-instruction :around
    (enclose-instruction
     call-instruction
     enter-instruction
     successor-instruction
     mapping)
  (let ((copy (find-in-mapping mapping successor-instruction)))
    (if (null copy)
        '()
        (call-next-method))))

(defun local-location-p (location)
  (eq (gethash location *location-ownerships*)
      *original-enter-instruction*))

(defun translate-inputs (inputs mapping)
  ;; An input is either already in the mapping, or else it is
  ;; is a location that is owned by some ancestor function.
  (loop for input in inputs
        for new = (find-in-mapping mapping input)
        collect (if (null new) input new)))

;;; An output can either be in the mapping, be a reference to a
;;; location owned by an ancestor function, or a local lexical
;;; location not yet in the mapping.  In the last case, a new location
;;; must be created, and it must be added to the mapping, to
;;; CALL-INSTRUCTION as an input, and to ENTER-INSTRUCTION as an
;;; output.
(defun translate-output (output call-instruction enter-instruction mapping)
  (let ((new (find-in-mapping mapping output)))
    (cond ((not (null new)) new)
          ((not (local-location-p output)) output)
          (t (setf new (cleavir-ir:new-temporary))
             (setf (cleavir-ir:inputs call-instruction)
                   (append
                    (cleavir-ir:inputs call-instruction)
                    (list new)))
             (setf (cleavir-ir:outputs enter-instruction)
                   (append
                    (cleavir-ir:outputs enter-instruction)
                    (list new)))
             (add-to-mapping mapping output new)
             new))))
    
(defun translate-outputs (outputs call-instruction enter-instruction mapping)
  (loop for output in outputs
        collect (translate-output output
                                  call-instruction
                                  enter-instruction
                                  mapping)))

(defmethod inline-one-instruction
    (enclose-instruction
     call-instruction
     enter-instruction
     (successor-instruction cleavir-ir:one-successor-mixin)
     mapping)
  (let* ((inputs (cleavir-ir:inputs successor-instruction))
         (new-inputs (translate-inputs inputs mapping))
         (outputs (cleavir-ir:outputs successor-instruction))
         (new-outputs (translate-outputs outputs
                                         call-instruction
                                         enter-instruction
                                         mapping))
         (new-instruction (make-instance (class-of successor-instruction)
                            :inputs new-inputs
                            :outputs new-outputs)))
    (add-to-mapping mapping successor-instruction new-instruction)
    (cleavir-ir:insert-instruction-before new-instruction enclose-instruction)
    (setf (cleavir-ir:successors enter-instruction)
          (list (cleavir-ir:successors successor-instruction)))
    (list (make-instance 'worklist-item
            :enclose-instruction enclose-instruction
            :call-instruction call-instruction
            :enter-instruction enter-instruction
            :mapping mapping))))

(defun add-two-successor-instruction-before-instruction
    (instruction-to-add
     before-instruction
     new-first-successor
     new-second-successor)
  ;; Start by setting the predecessors of the instruction to add to be
  ;; the current predecessors of the instruction before which the
  ;; new instruction is to be added.
  (setf (cleavir-ir:predecessors instruction-to-add)
        (cleavir-ir:predecessors before-instruction))
  ;; It is possible that BEFORE-INSTRUCTION has more than one
  ;; predecessor.  And it is possible that each one of those
  ;; predecessors has more than one successor. So for each such
  ;; predecessor, replace BEFORE-INSTRUCTION by INSTRUCTION-TO-ADD in
  ;; its list of successors.
  (loop for predecessor in (cleavir-ir:predecessors before-instruction)
        do (setf (cleavir-ir:successors predecessor)
                 (substitute instruction-to-add
                             before-instruction
                             (cleavir-ir:successors predecessor))))
  ;; Set the successors of the instruction to add to be the list of
  ;; the two successors we were given as arguments.
  (setf (cleavir-ir:successors instruction-to-add)
        (list new-first-successor new-second-successor))
  ;; Each of the two successors we were given as arguments will now
  ;; have a single predecessor, namely INSTRUCTION-TO-ADD, so we set
  ;; the list of predecessors of each one to a singleton list of
  ;; INSTRUCTION-TO-ADD.
  (setf (cleavir-ir:predecessors new-first-successor)
        (list instruction-to-add))
  (setf (cleavir-ir:predecessors new-second-successor)
        (list instruction-to-add)))