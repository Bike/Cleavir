(cl:in-package #:cleavir-cst-to-ast)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a symbol that has a definition as a symbol macro.

(defmethod convert-cst
    (cst (info trucler:symbol-macro-description) env system)
  (let* ((expansion (trucler:expansion info))
         (expander (symbol-macro-expander expansion))
         (expanded-form (expand-macro expander cst env))
         (expanded-cst (cst:reconstruct expanded-form cst system)))
    (with-preserved-toplevel-ness
      (convert expanded-cst env system))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a symbol that has a definition as a constant variable.

(defmethod convert-cst
    (cst (info trucler:constant-variable-description) env system)
  (declare (ignore cst))
  (let ((cst (cst:cst-from-expression (trucler:value info))))
    (convert-constant cst env system)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a special form represented as a CST.

(defmethod convert-cst
    (cst (info trucler:special-operator-description) env system)
  (convert-special (car (cst:raw cst)) cst env system))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a compound form that calls a local macro.
;;; A local macro can not have a compiler macro associated with it.
;;;
;;; If we found a local macro in ENV, it means that ENV is not the
;;; global environment.  And it must be the same kind of agumentation
;;; environment that was used when the local macro was created by the
;;; use of MACROLET.  Therefore, the expander should be able to handle
;;; being passed the same kind of environment.

(defmethod convert-cst
    (cst (info trucler:local-macro-description) env system)
  (let* ((expander (trucler:expander info))
         (expanded-form (expand-macro expander cst env))
         (expanded-cst (cst:reconstruct expanded-form cst system)))
    (with-preserved-toplevel-ness
      (convert expanded-cst env system))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a compound form that calls a global macro.
;;; A global macro can have a compiler macro associated with it.

(defmethod convert-cst
    (cst (info trucler:global-macro-description) env system)
  (let ((compiler-macro (trucler:compiler-macro info))
        (expander (trucler:expander info)))
    (with-preserved-toplevel-ness
      (if (null compiler-macro)
          ;; There is no compiler macro, so we just apply the macro
          ;; expander, and then convert the resulting form.
          (let* ((expanded-form (expand-macro expander cst env))
                 (expanded-cst (cst:reconstruct expanded-form cst system)))
            (convert expanded-cst env system))
          ;; There is a compiler macro, so we must see whether it will
          ;; accept or decline.
          (let ((expanded-form (expand-compiler-macro compiler-macro cst env)))
            (if (eq (cst:raw cst) expanded-form)
                ;; If the two are EQ, this means that the compiler macro
                ;; declined.  Then we appply the macro function, and
                ;; then convert the resulting form, just like we did
                ;; when there was no compiler macro present.
                (let* ((expanded-form
                         (expand-macro expander cst env))
                       (expanded-cst (cst:reconstruct expanded-form cst system)))
                  (convert expanded-cst env system))
                ;; If the two are not EQ, this means that the compiler
                ;; macro replaced the original form with a new form.
                ;; This new form must then again be converted without
                ;; taking into account the real macro expander.
                (let ((expanded-cst (cst:reconstruct expanded-form cst system)))
                  (convert expanded-cst env system))))))))

;;; Construct a CALL-AST representing a function-call form.  CST is
;;; the concrete syntax tree representing the entire function-call
;;; form.  ARGUMENTS-CST is a CST representing the sequence of
;;; arguments to the call.
(defun make-call (cst info env arguments-cst system)
  (check-cst-proper-list cst 'form-must-be-proper-list)
  (let* ((name-cst (cst:first cst))
         (function-ast
           (convert-called-function-reference name-cst info env system))
         (argument-asts (convert-sequence arguments-cst env system))
         (origin (cst:source cst))
         (ftype (first (trucler:type info))))
    (let ((required (cleavir-ctype:function-required ftype system))
          (optional (cleavir-ctype:function-optional ftype system))
          (rest (cleavir-ctype:function-rest ftype system))
          (keysp (cleavir-ctype:function-keysp ftype system))
          (values (cleavir-ctype:function-values ftype system)))
      (type-wrap-return-values
       (cleavir-ast:make-call-ast function-ast
                                  (mapcar
                                   (lambda (argument-ast)
                                     (type-wrap-argument
                                      argument-ast
                                      ;; FIXME: figure out if we need
                                      ;; this to be a values
                                      ;; specifier.
                                      (cleavir-ctype:coerce-to-values
                                       (cond (required (pop required))
                                             (optional (pop optional))
                                             ;; FIXME: Actually treat &key properly!
                                             (keysp t)
                                             (t (if (cleavir-ctype:bottom-p rest system)
                                                    (progn
                                                      ;; FIXME: Use a
                                                      ;; condition
                                                      ;; class here.
                                                      (warn "A call to ~a was passed a number of arguments incompatible with its declared type ~a."
                                                            (cst:raw name-cst) ftype)
                                                      ;; Without this
                                                      ;; we'll get a
                                                      ;; borked call
                                                      ;; as a result.
                                                      (cleavir-ctype:top system))
                                                    rest)))
                                       system)
                                      origin env system))
                                   argument-asts)
                                  :origin origin
                                  ;;:attributes (cleavir-env:attributes info)
                                  ;;:transforms (cleavir-env:transforms info)
                                  :inline (trucler:inline info))
       values
       origin
       env
       system))))

;;; Convert a form representing a call to a named global function.
;;; CST is the concrete syntax tree representing the entire
;;; function-call form.  INFO is the info instance returned form a
;;; query of the environment with the name of the function.
(defmethod convert-cst
    (cst (info trucler:global-function-description) env system)
  ;; When we compile a call to a global function, it is possible that
  ;; we are in COMPILE-TIME-TOO mode.  In that case, we must first
  ;; evaluate the form.
  (when (and *current-form-is-top-level-p* *compile-time-too*)
    (cst-eval-for-effect-encapsulated cst env system))
  (let ((compiler-macro (trucler:compiler-macro info))
        (notinline (eq 'notinline (trucler:inline info))))
    (if (or notinline (null compiler-macro))
        ;; There is no compiler macro.  Create the call.
        (make-call cst info env (cst:rest cst) system)
        ;; There is a compiler macro.  We must see whether it will
        ;; accept or decline.
        (let ((expanded-form (expand-compiler-macro compiler-macro cst env)))
          (if (eq (cst:raw cst) expanded-form)
              ;; If the two are EQ, this means that the compiler macro
              ;; declined.  We are left with function-call form.
              ;; Create the call, just as if there were no compiler
              ;; macro present.
              (make-call cst info env (cst:rest cst) system)
              ;; If the two are not EQ, this means that the compiler
              ;; macro replaced the original form with a new form.
              ;; This new form must then be converted.
              (let ((expanded-cst (cst:reconstruct expanded-form cst system)))
                (convert expanded-cst env system)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a CST representing a compound form that calls a local
;;; function.  A local function can not have a compiler macro
;;; associated with it.

(defmethod convert-cst
    (cst (info trucler:local-function-description) env system)
  (make-call cst info env (cst:rest cst) system))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a symbol that has a definition as a special variable.
;;; We do this by generating a call to SYMBOL-VALUE.

(defmethod convert-special-variable (cst info global-env system)
  (declare (ignore global-env system))
  (let ((symbol (trucler:name info))
        (origin (cst:source cst)))
    (cleavir-ast:make-symbol-value-ast
     (cleavir-ast:make-constant-ast symbol :origin origin)
     :origin origin)))

(defmethod convert-cst
    (cst (info trucler:special-variable-description) env system)
  (let ((global-env (trucler:global-environment env)))
    (convert-special-variable cst info global-env system)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a symbol that has a definition as a lexical variable.

(defmethod convert-cst
    (cst (info trucler:lexical-variable-description) env system)
  (when (eq (trucler:ignore info) 'ignore)
    (warn 'ignored-variable-referenced :cst cst))
  (let ((origin (cst:source cst)))
    (type-wrap (cleavir-ast:make-lexical-ast (trucler:identity info)
                 :origin origin)
               (cleavir-ctype:coerce-to-values (trucler:type info) system)
               origin
               env
               system)))
