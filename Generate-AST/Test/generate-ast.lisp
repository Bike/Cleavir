(in-package #:cleavir-test-generate-ast)

(defgeneric same-p (ast1 ast2))

(defvar *table*)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Testing framework.

(defparameter *e* (make-instance 'bogus-environment))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf *readtable* cleavir-io:*io-readtable*))

(defun test (form value)
  (let* ((ast (cleavir-generate-ast:generate-ast form *e*))
	 (v (cleavir-ast-interpreter:interpret ast)))
    (assert (equalp v value))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Tests

(defun test-constant-ast ()
  (test 234 234))

(defun test-lexical-ast ()
  (test '(let ((x 10)) x)
	10))

(defun test-symbol-value-ast ()
  (test '*print-base*
	10))

(defun test-block-return-from-ast ()
  (test '(block x (return-from x 10) 20)
	10))

(defun test-if-ast ()
  (test '(if t 10 20)
	10)
  (test '(if nil 10 20)
	20))

(defun test-tagbody-ast ()
  (test '(let ((x 1)) (tagbody (setq x 2) (go a) (setq x 3) a) x)
	2))

(defun test-fdefinition-ast ()
  (test '(function car)
	#'car))

(defun test-call ()
  (test '(1+ *print-base*)
	11)
  (test '(flet ((f () 1))
	  (+ (f) 2))
	3)
  (test '(flet ((f (x) x))
	  (+ (f 1) 2))
	3)
  (test '(flet ((f (x) x)
		(g (x) x))
	  (+ (f 1) (g 2)))
	3)
  (test '(flet ((f (x &optional (y 234)) (+ x y)))
	  (f 10))
	244)
  (test '(flet ((f (x &optional (y 234)) (+ x y)))
	  (f 10 20))
	30)
  (test '(flet ((f (x) (+ x 1))
		(g (x) (+ x 2)))
	  (+ (f 10) (g 20)))
	33)
  (test '(flet ((f (x &optional (y 234) (z (1+ y))) (+ x y z)))
	  (f 10 20 30))
	60)
  (test '(flet ((f (x &optional (y 234) (z (1+ y))) (+ x y z)))
	  (f 10 20))
	51)
  (test '(flet ((f (x &optional (y 234) (z (1+ y))) (+ x y z)))
	  (f 10))
	479)
  (test '(flet ((f (&key x) x))
	  (f))
	nil)
  (test '(flet ((f (&key x) x))
	  (f :x 10))
	10)
  (test '(flet ((f (&key (x 10) (y 20)) (list x y)))
	  (f))
	'(10 20))
  (test '(flet ((f (&key (x 10) (y 20)) (list x y)))
	  (f :x 'a))
	'(a 20))
  (test '(flet ((f (&key (x 10) (y 20)) (list x y)))
	  (f :y 'a))
	'(10 a))
  (test '(flet ((f (&key (x 10) (y (1+ x))) (list x y)))
	  (f :y 'a))
	'(10 a))
  (test '(flet ((f (&key (x 10) (y (1+ x))) (list x y)))
	  (f))
	'(10 11))
  (test '(flet ((f (&key (x 10) (y (1+ x))) (list x y)))
	  (f :x 20))
	'(20 21)))

(defun run-tests ()
  (test-constant-ast)
  (test-lexical-ast)
  (test-symbol-value-ast)
  (test-block-return-from-ast)
  (test-if-ast)
  (test-tagbody-ast)
  (test-fdefinition-ast)
  (test-call))
