(cl:in-package #:common-lisp-user)

(defpackage #:cleavir-test-minimal-compilation
  (:use #:common-lisp))

(in-package #:cleavir-test-minimal-compilation)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defclass bogus-environment () ()))

(defparameter *e* (make-instance 'bogus-environment))

;;; Any variable not otherwise mentioned explicitly is considered to
;;; be a special variable.
(defmethod cleavir-env:variable-info
    ((environment bogus-environment) symbol)
  (make-instance 'cleavir-env:special-variable-info
    :name symbol))

;;; Any function not otherwise mentioned explicitly is considered to
;;; be a global function.
(defmethod cleavir-env:function-info
    ((environment bogus-environment) name)
  (make-instance 'cleavir-env:global-function-info
    :name name))

;;; When the name UNDEFINED-VARIABLE is used as a global variable,
;;; then return NIL to indicate that there is no such variable.
(defmethod cleavir-env:variable-info
    ((environment bogus-environment) (name (eql 'undefined-variable)))
  nil)

;;; When the name GSM1 is used as a global variable, then it is
;;; considered a global symbol macro that expands to the following
;;; form: (HELLO1 HELLO2)
(defmethod cleavir-env:variable-info
    ((environment bogus-environment) (name (eql 'gsm1)))
  (make-instance 'cleavir-env:symbol-macro-info 
    :name name
    :expansion '(hello1 hello2)))

;;; When the name GSM2 is used as a global variable, then it is
;;; considered a global symbol macro that expands to the following
;;; form: GSM1
(defmethod cleavir-env:variable-info
    ((environment bogus-environment) (name (eql 'gsm2)))
  (make-instance 'cleavir-env:symbol-macro-info 
    :name name
    :expansion 'gsm1))

;;; When the name UNDEFINED-FUNCTION is used as a global function,
;;; then return NIL to indicate that there is no such function.
(defmethod cleavir-env:function-info
    ((environment bogus-environment) (name (eql 'undefined-function)))
  nil)

;;; When the name GM1 is used as a global function, then it is
;;; considered a global macro that expands to the following form:
;;; (HELLO <arg>) where <arg> is the argument given to the macro
(defmethod cleavir-env:function-info
    ((environment bogus-environment) (name (eql 'gm1)))
  (make-instance 'cleavir-env:global-macro-info 
    :name name
    :expander (lambda (form env)
		(declare (ignore env))
		`(hello ,(second form)))
    :compiler-macro nil))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *special-operators*
    '(block catch eval-when flet function go if labels let let* load-time-value
      locally macrolet multiple-value-call multiple-value-prog1 progn progv
      quote return-from setq symbol-macrolet tagbody the throw unwind-protect)))

;;; Add some special operators to the environment.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (loop for operator in *special-operators*
	do (eval `(defmethod cleavir-env:function-info
		      ((environment bogus-environment) (name (eql ',operator)))
		    (make-instance 'cleavir-env:special-operator-info
		      :name name)))))

;;; When the name LET is used as a global function, then it is
;;; considered a special operator.
(defmethod cleavir-env:function-info
    ((environment bogus-environment) (name (eql 'let)))
  (make-instance 'cleavir-env:special-operator-info
     :name name))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test BLOCK

(defun test-block ()
  ;; Check that the name of the block is not expanded, but that the
  ;; body forms are.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(block gsm1 gsm1 gsm1)
		  *e*)
		 '(block gsm1 (hello1 hello2) (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test CATCH

(defun test-catch ()
  ;; Check that the all the arguments are expanded.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(catch gsm1 gsm1)
		  *e*)
		 '(catch (hello1 hello2) (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test EVAL-WHEN

(defun test-eval-when ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(eval-when (:compile-toplevel)
		    gsm1 gsm1)
		  *e*)
		 '(eval-when (:compile-toplevel)
		   (hello1 hello2) (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test FLET

(defun test-flet ()
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the &OPTIONAL part of the lambda list of
  ;; the local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (gsm1 &optional (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (gsm1 &optional (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the &KEY part of the lambda list of
  ;; the local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (gsm1 &key (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (gsm1 &key ((:x x) gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the &AUX part of the lambda list of
  ;; the local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (gsm1 &aux (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (gsm1 &aux (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the body of the local function, but not in
  ;; the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (gsm1) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (gsm1) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in the &KEY part of the lambda list of
  ;; the local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&optional (gsm1 12) &key (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&optional (gsm1 12) &key ((:x x) gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in the remaining &OPTIONAL part of the
  ;; lambda list of the local function, but not in the body of the
  ;; FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&optional (gsm1 12) (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&optional (gsm1 12) (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in the &AUX part of the lambda list of
  ;; the local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&optional (gsm1 12) &aux (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&optional (gsm1 12) &aux (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in body of the local function, but not in
  ;; the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&optional (gsm1 12)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&optional (gsm1 12)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &KEY parameter of the local function shadows the
  ;; global symbol macro in the remaining &KEY part of the lambda list
  ;; of the local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&key (gsm1 12) (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&key ((:gsm1 gsm1) 12) ((:x x) gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &KEY parameter of the local function shadows the
  ;; global symbol macro in the &AUX part of the lambda list of the
  ;; local function, but not in the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&key (gsm1 12) &aux (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&key ((:gsm1 gsm1) 12) &aux (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &KEY parameter of the local function shadows the
  ;; global symbol macro in the body of the local function, but not in
  ;; the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&key (gsm1 12)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&key ((:gsm1 gsm1) 12)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &AUX parameter of the local function shadows
  ;; the global symbol macro in the remaining &AUX part of the
  ;; lambda list of the local function, but not in the body of the
  ;; FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&aux (gsm1 12) (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&aux (gsm1 12) (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &AUX parameter of the local function shadows the
  ;; global symbol macro in the body of the local function, but not in
  ;; the body of the FLET.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(flet ((fun (&aux (gsm1 12)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(flet ((fun (&aux (gsm1 12)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that the name of the local function shadows the global macro
  ;; in the body of the flet, but not in the body of the local
  ;; function.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(flet ((gm1 (x) (gm1 x)))
		    (gm1 x))
		  *e*)
		 '(flet ((gm1 (x) (hello x)))
		   (gm1 x))))
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(flet ((fun1 (x &optional (y gsm1))
			   (f x y gsm1))
			  (fun2 (x &key (y gsm1 gsm1))
			   (f x y gsm1)))
		    gsm1)
		  *e*)
		 '(flet ((fun1 (x &optional (y (hello1 hello2)))
			  (f x y (hello1 hello2)))
			 (fun2 (x &key ((:y y) (hello1 hello2) gsm1))
			  (f x y gsm1)))
		   (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test FUNCTION

(defun test-function ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(function fff)
		  *e*)
		 '(function fff)))
  ;;; Test that the name of the function is not expanded as a symbol
  ;;; macro.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(function gsm1)
		  *e*)
		 '(function gsm1)))
  ;;; Test that required parameter of lambda expression shadows global
  ;;; symbol macro inside the body of the lambda expression.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(function (lambda (gsm1) gsm1))
		  *e*)
		 '(function (lambda (gsm1) gsm1)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test GO

(defun test-go ()
  ;; Check that that the argument of GO is not compiled.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(go gsm1)
		  *e*)
		 '(go gsm1))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test IF

(defun test-if ()
  ;; Check that all three arguments of IF are minimally compiled.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(if gsm1 gsm1 gsm1)
		  *e*)
		 `(if (hello1 hello2) (hello1 hello2) (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test LABELS

(defun test-labels ()
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the &OPTIONAL part of the lambda list of
  ;; the local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (gsm1 &optional (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (gsm1 &optional (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the &KEY part of the lambda list of
  ;; the local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (gsm1 &key (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (gsm1 &key ((:x x) gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the &AUX part of the lambda list of
  ;; the local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (gsm1 &aux (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (gsm1 &aux (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that a required parameter of the local function shadows the
  ;; global symbol macro in the body of the local function, but not in
  ;; the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (gsm1) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (gsm1) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in the &KEY part of the lambda list of
  ;; the local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&optional (gsm1 12) &key (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&optional (gsm1 12) &key ((:x x) gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in the remaining &OPTIONAL part of the
  ;; lambda list of the local function, but not in the body of the
  ;; LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&optional (gsm1 12) (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&optional (gsm1 12) (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in the &AUX part of the lambda list of
  ;; the local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&optional (gsm1 12) &aux (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&optional (gsm1 12) &aux (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &OPTIONAL parameter of the local function shadows
  ;; the global symbol macro in body of the local function, but not in
  ;; the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&optional (gsm1 12)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&optional (gsm1 12)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &KEY parameter of the local function shadows the
  ;; global symbol macro in the remaining &KEY part of the lambda list
  ;; of the local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&key (gsm1 12) (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&key ((:gsm1 gsm1) 12) ((:x x) gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &KEY parameter of the local function shadows the
  ;; global symbol macro in the &AUX part of the lambda list of the
  ;; local function, but not in the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&key (gsm1 12) &aux (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&key ((:gsm1 gsm1) 12) &aux (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &KEY parameter of the local function shadows the
  ;; global symbol macro in the body of the local function, but not in
  ;; the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&key (gsm1 12)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&key ((:gsm1 gsm1) 12)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &AUX parameter of the local function shadows
  ;; the global symbol macro in the remaining &AUX part of the
  ;; lambda list of the local function, but not in the body of the
  ;; LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&aux (gsm1 12) (x gsm1)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&aux (gsm1 12) (x gsm1)) gsm1))
		    (fun (hello1 hello2)))))
  ;; Test that an &AUX parameter of the local function shadows the
  ;; global symbol macro in the body of the local function, but not in
  ;; the body of the LABELS.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  `(labels ((fun (&aux (gsm1 12)) gsm1))
		     (fun gsm1))
		  *e*)
		 `(labels ((fun (&aux (gsm1 12)) gsm1))
		    (fun (hello1 hello2))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test LET

(defun test-let ()
  ;; Check that the symbol macro is not shadowed by the first variable
  ;; binding.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(let ((gsm1 10)
			 (var gsm1))
		    x)
		  *e*)
		 '(let ((gsm1 10) (var (hello1 hello2))) x)))
  ;; Check that a local variable shadows the global symbol macro with
  ;; the same name.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(let ((gsm1 10)) (gsm1 gsm1))
		  *e*)
		 '(let ((gsm1 10)) (gsm1 gsm1)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test LET*

(defun test-let* ()
  ;; Check that the symbol-macro is shadowed by the first variable
  ;; binding.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(let* ((gsm1 10)
			 (var gsm1))
		    x)
		  *e*)
		 '(let* ((gsm1 10) (var gsm1)) x)))
  ;; Check that a local variable shadows the global symbol macro with
  ;; the same name.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(let* ((gsm1 10)) (gsm1 gsm1))
		  *e*)
		 '(let* ((gsm1 10)) (gsm1 gsm1)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test LOAD-TIME-VALUE

(defun test-load-time-value ()
  ;; Check that the first argument of LOAD-TIME-VALUE is minimally
  ;; compiled, and that the second argument is preserved intact.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(load-time-value gsm1 t)
		  *e*)
		 '(load-time-value (hello1 hello2) t))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test LOCALLY

(defun test-locally ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(locally gsm1)
		  *e*)
		 '(locally (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test MACROLET

(defun test-macrolet ()
  ;; Test that a call to the local macro is expanded.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(macrolet ((gm1 (a b) `(cons ,a ,b)))
		    (gm1 x y))
		  *e*)
		 '(locally (cons x y)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test MULTIPLE-VALUE-CALL.

(defun test-multiple-value-call ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(multiple-value-call gsm1 gsm1 gsm1)
		  *e*)
		 '(multiple-value-call
		   (hello1 hello2) (hello1 hello2) (hello1 hello2)))))
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test MULTIPLE-VALUE-PROG1.

(defun test-multiple-value-prog1 ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(multiple-value-prog1 gsm1 gsm1 gsm1)
		  *e*)
		 '(multiple-value-prog1
		   (hello1 hello2) (hello1 hello2) (hello1 hello2)))))
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test PROGN

(defun test-progn ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(progn gsm1 gsm1)
		  *e*)
		 '(progn (hello1 hello2) (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test PROGV

(defun test-progv ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(progv gsm1 gsm1 gsm1 gsm1)
		  *e*)
		 '(progv (hello1 hello2) (hello1 hello2)
		   (hello1 hello2) (hello1 hello2)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test SETQ

(defun test-setq ()
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(setq x gsm1 y gsm1)
		  *e*)
		 `(progn (setq x (hello1 hello2))
			 (setq y (hello1 hello2)))))
  ;; Check that the second gsm1 is expanded.  SETQ is handled as SETF
  ;; if the variable is defined as a symbol macro.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(setq x gsm1 gsm1 z)
		  *e*)
		 `(progn (setq x (hello1 hello2))
			 (setf (hello1 hello2) z)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Global function for running all the tests.

(defun run-tests ()
  (test-block)
  (test-catch)
  (test-eval-when)
  (test-flet)
  (test-function)
  (test-go)
  (test-if)
  (test-labels)
  (test-let)
  (test-let*)
  (test-load-time-value)
  (test-locally)
  (test-macrolet)
  (test-multiple-value-call)
  (test-multiple-value-prog1)
  (test-progn)
  (test-progv)
  (test-setq)
  (assert (equal (cleavir-generate-ast:minimally-compile
		  'hello
		  *e*)
		 'hello))
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(hello)
		  *e*)
		 '(hello)))
  ;; Check that the symbol macro is expanded correctly.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  'gsm1
		  *e*)
		 '(hello1 hello2)))
  ;; Check that the symbol macro is expanded correctly and that the
  ;; expansion is then minimally compiled.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  'gsm2
		  *e*)
		 '(hello1 hello2)))
  ;; Check that the symbol macro is expanded in an argument position,
  ;; but not in a function position.
  (assert (equal (cleavir-generate-ast:minimally-compile
		  '(gsm1 gsm1)
		  *e*)
		 '(gsm1 (hello1 hello2))))
  (format t "Tests passed~%"))

(run-tests)
