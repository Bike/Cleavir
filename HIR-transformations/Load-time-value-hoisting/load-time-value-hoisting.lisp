(cl:in-package #:cleavir-load-time-value-hoisting)

;;; The purpose of this transformation is to replace all non-immediate
;;; constants and load-time-value inputs by outputs of some sequences of
;;; instructions, and to arrange that these instructions are executed at
;;; load time and in the correct order.
;;;
;;; Some parts of this transformation are necessarily client specific,
;;; e.g., it is not possible to reconstruct a symbol at load time by means
;;; of (funcall 'intern name package), because intern is itself a symbol,
;;; leading to infinite recursion.  The following client specific methods
;;; are mandatory for this transformation to succeed:
;;;
;;; - A default method on HIR-FROM-FORM, that converts a form to the
;;;   corresponding HIR.
;;;
;;; - A default method on MAKE-LOAD-FORM-USING-CLIENT that calls
;;;   MAKE-LOAD-FORM with a suitable environment.
;;;
;;; - Specialized methods on MAKE-LOAD-FORM-USING-CLIENT for symbols and
;;;   strings.  The given defaults are merely for illustration result in
;;;   infinitely recursive definitions.
;;;
;;; In addition to the above methods, clients should adapt the behavior of
;;; IMMEDIATE-P and EQUALP-KEYS to their needs.

(defun hoist-load-time-values (hir system)
  (with-constructor-tables
    (scan-hir hir system)
    (hoist-toplevel-hir hir system)))
