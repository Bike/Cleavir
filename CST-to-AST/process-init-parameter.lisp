(cl:in-package #:cleavir-cst-to-ast)

;;; VAR-AST and SUPPLIED-P-AST are LEXICAL-ASTs that will be set by
;;; the implementation-specific argument-parsing code, according to
;;; what arguments were given.  VALUE-AST is an AST that computes the
;;; initialization for the variable to be used when no explicit value
;;; is supplied by the caller.  This function generates the code for
;;; testing whether SUPPLIED-P-AST computes NIL or T, and for
;;; assigning the value computed by VALUE-AST to VAR-AST if
;;; SUPPLIED-P-AST computes NIL.
(defun make-initialization-ast (var-ast supplied-p-ast value-ast env system)
  (let ((nil-cst (cst:cst-from-expression nil)))
    (cleavir-ast:make-if-ast
     (cleavir-ast:make-eq-ast
      supplied-p-ast
      (convert-constant nil-cst env system))
     (cleavir-ast:make-setq-ast var-ast value-ast)
     (convert-constant nil-cst env system))))

;;; VAR-CST and SUPPLIED-P-CST are CSTs representing a parameter
;;; variable and its associated SUPPLIED-P variable. If no associated
;;; SUPPLIED-P variable is present in the lambda list then
;;; SUPPLIED-P-CST is NIL.  INIT-AST is the AST that computes the
;;; value to be assigned to the variable represented by VAR-CST if no
;;; argument was supplied for it.  ENV is an environment that already
;;; contains the variables corresponding to VAR-CST and SUPPLIED-P-CST
;;; (if it is not NIL).
;;;
;;; This function returns two values.  The first value is an AST that
;;; represents both the processing of this parameter AND the
;;; computation that follows.  We can not return an AST only for this
;;; computation, because if either one of the variables represented by
;;; VAR-CST or SUPPLIED-P-CST is special, then NEXT-AST must be in the
;;; body of a BIND-AST generated by this function.  The second return
;;; value is a list of two LEXICAL-ASTs.  The first lexical AST
;;; corresponds to VAR-CST and the second to SUPPLIED-P-CST.  The
;;; implementation-specific argument-parsing code is responsible for
;;; assigning to those LEXICAL-ASTs according to what arguments were
;;; given to the function.
(defun process-init-parameter
    (var-cst supplied-p-cst init-ast env next-ast system)
  (let* ((var (cst:raw var-cst))
         (name1 (make-symbol (string-downcase var)))
	 (lexical-var-ast (cleavir-ast:make-lexical-ast
                           name1 :origin (cst:source var-cst)))
         (supplied-p (cst:raw supplied-p-cst))
	 (name2 (if (null supplied-p)
		    (gensym)
		    (make-symbol (string-downcase supplied-p))))
	 (lexical-supplied-p-ast (cleavir-ast:make-lexical-ast
                                  name2 :origin (cst:source supplied-p-cst))))
    (values (process-progn
	     (list (make-initialization-ast lexical-var-ast
					    lexical-supplied-p-ast
					    init-ast
					    env
					    system)
		   (set-or-bind-variable
		    var-cst
		    lexical-var-ast
		    (if (null supplied-p-cst)
			next-ast
			(set-or-bind-variable
			 supplied-p-cst
			 lexical-supplied-p-ast
			 next-ast
			 env
			 system))
		    env
		    system)))
	    (list lexical-var-ast lexical-supplied-p-ast))))
