(in-package #:cleavir-bir-transformations)

;;; We just attempted to detect local calls. See if anything is worth
;;; doing after. FIXME: Think of a nice CLOSy way to make this optional
;;; and specializable.
(defun post-find-local-calls (function)
  ;; When a function has no encloses and has only one local call, it
  ;; is eligible for interpolation.
  (when (and (cleavir-set:empty-set-p (cleavir-bir:encloses function))
             (lambda-list-inlinable-p (cleavir-bir:lambda-list function)))
    ;; FIXME: We could contify more generally here.
    (let* ((local-calls (cleavir-bir:local-calls function))
           (nlocalcalls (cleavir-set:size local-calls)))
      (cond ((zerop nlocalcalls))
            ((= nlocalcalls 1)
             (interpolate-function (cleavir-set:arb local-calls)))
            #+(or)
            (t
             (cleavir-set:doset (c local-calls)
               (let ((copy (copy-function function))
                     (module (cleavir-bir:module function)))
                 (assert (cleavir-set:presentp copy (cleavir-bir:functions module)))
                 (cleavir-bir:verify (cleavir-bir:module function))
                 (setf (first (cleavir-bir:inputs c)) copy)
                 (interpolate-function c)
                 (assert (not (cleavir-set:presentp copy (cleavir-bir:functions module))))
                 (cleavir-bir:verify (cleavir-bir:module function)))))))))

;; required parameters only. rip.
(defun lambda-list-inlinable-p (lambda-list)
  (every (lambda (a) (typep a 'cleavir-bir:argument)) lambda-list))

;;; Return true if the call arguments are compatible with those of the function.
;;; If they're not, warn and return false.
(defun check-argument-list-compatible (arguments function)
  (let ((lambda-list (cleavir-bir:lambda-list function)))
    (let ((nsupplied (length arguments))
          (nrequired (length lambda-list)))
      (if (= nsupplied nrequired)
          t
          (warn "Expected ~a required arguments but got ~a arguments for function ~a."
                nrequired nsupplied (cleavir-bir:name function))))))

;;; Detect calls to a function via its closure and mark them as direct
;;; local calls to the function, doing compile time argument
;;; checking. If there are no more references to the closure, we can
;;; clean it up. This allows us to avoid allocating closures for
;;; functions which only have local calls. If the call arguments and
;;; the lambda list are not compatible, flame and do not convert so we
;;; can get a runtime error. This also serves as a sort of "escape
;;; analysis" for functions, recording the result of the analysis
;;; directly into the IR.
(defun find-function-local-calls (function)
  ;; FIXME: Arg parsing code not yet written!
  (when (lambda-list-inlinable-p (cleavir-bir:lambda-list function))
    (cleavir-set:doset (enclose (cleavir-bir:encloses function))
      (when (cleavir-bir:unused-p enclose)
        ;; FIXME: Note this dead code.
        (cleavir-bir:delete-computation enclose)
        (return-from find-function-local-calls))
      (let ((use (cleavir-bir:use enclose)))
        (typecase use
          (cleavir-bir:call
           (when (eq enclose (cleavir-bir:callee use))
             (when (check-argument-list-compatible (rest (cleavir-bir:inputs use))
                                                   function)
               (change-class use 'cleavir-bir:local-call)
               (cleavir-bir:replace-computation enclose function)))
           (when (cleavir-bir:unused-p enclose)
             (cleavir-bir:delete-computation enclose)))
          (cleavir-bir:writevar
           (let ((variable (first (cleavir-bir:outputs use))))
             ;; Variable needs to be immutable since we want to make
             ;; sure this definition reaches the readers.
             (when (cleavir-bir:immutablep variable)
               (cleavir-set:doset (reader (cleavir-bir:readers variable))
                 (unless (cleavir-bir:unused-p reader)
                   (let ((use (cleavir-bir:use reader)))
                     (typecase use
                       (cleavir-bir:call
                        (when (eq reader (cleavir-bir:callee use))
                          (when (check-argument-list-compatible
                                 (rest (cleavir-bir:inputs use))
                                 function)
                            (change-class use 'cleavir-bir:local-call)
                            (cleavir-bir:replace-computation reader function)))))))))
             ;; No more references to the variable means we can clean up
             ;; the writer and enclose.
             (when (cleavir-set:empty-set-p (cleavir-bir:readers variable))
               (cleavir-bir:delete-instruction use)
               (cleavir-bir:delete-computation enclose)))))))
    (post-find-local-calls function)))

(defun find-module-local-calls (module)
  (cleavir-set:mapset nil #'find-function-local-calls
                      (cleavir-bir:functions module)))
