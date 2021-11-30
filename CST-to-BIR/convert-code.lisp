(cl:in-package #:cleavir-cst-to-bir)

;;;; The general method for processing the lambda list is as follows:
;;;; We use recursion to process the remaining lambda list. Before
;;;; the recursive call, we add the current parameters to the
;;;; environment that we pass to the recursive call.  The call returns
;;;; two values: the AST that was built and a modified lambda list,
;;;; containing the lambda list keywords, and the lexical variables
;;;; that were introduced.  The exception is that processing &AUX
;;;; entries does not return any lambda list, because it will always
;;;; be empty.
;;;;
;;;; The reason we do it this way is that, if a parameter turns out to
;;;; be a special variable, the entire rest of the lambda list and
;;;; function body must be executed with this variable bound.  The AST
;;;; configuration for expressing that situation is that the AST for
;;;; computing the rest of the lambda list and the body must be a
;;;; child of a BIND-AST that indicates that the special variable
;;;; should be bound.  This recursive method makes sure that the child
;;;; exists before the BIND-AST is created.
;;;;
;;;; The parameter DSPECS that is used in several functions is a list
;;;; of canonicalized declaration specifiers.  This list is used to
;;;; determine whether a variable is declared special.

;;;; Several functions in this system create a LEXICAL LAMBDA LIST.
;;;; Such a lambda list is similar to an ordinary lambda list.  It can
;;;; have required parameter, &OPTIONAL parameters, a &REST parameter,
;;;; and &KEY parameters.  It can not have any &AUX parameters,
;;;; though.  It can also have implementation-specific parameters.
;;;; The parameters are different from those of an ordinary lambda
;;;; list.  A required parameter is represented as a LEXICAL-VARIABLE
;;;; corresponding to the variable of the parameter in the original
;;;; lambda list.  The same thing is true for a &REST parameter.  An
;;;; &OPTIONAL parameter is represented as a list of two LEXICAL-VARIABLEs.
;;;; The first AST of the list corresponds to the variable of the
;;;; parameter in the original lambda list, and the second AST
;;;; corresponds to a SUPPLIED-P parameter, whether the original
;;;; lambda list had such a parameter or not.  We generate ASTs that
;;;; test the SUPPLIED-P parameter and, if it is NIL, compute the
;;;; value of the initialization form if the corresponding parameter.
;;;; A &KEY parameter is represented as a list of three elements.  The
;;;; first element is the keyword to be used to determine whether this
;;;; parameter was given.  The remaining two elements play the same
;;;; role as those of an &OPTIONAL parameter.  We are not concerned
;;;; here with they way in which it is determined whether a particular
;;;; &KEY parameter was given or not.  This logic is determined for
;;;; each implementation.

;;; Process a single parameter. This function first computes a new
;;; environment by augmenting ENVIRONMENT with information from
;;; PARAMETER. Then it generates BIR to bind the parameter.
;;; Finally, it calls PROCESS-PARAMETERS-IN-GROUP with the new
;;; environment to continue processing the lambda list.
(defgeneric process-parameter
    (parameter remaining-parameters-in-group
     remaining-parameter-groups
     idspecs-of-parameter remaining-idspecs-in-group remaining-idspecs
     entry-of-parameter remaining-entries-in-group remaining-entries
     inserter environment system))

;;; Process all the parameters in the list PARAMETERS-IN-GROUP.  This
;;; function first computes a new environment by augmenting
;;; ENVIRONMENT with information from the parameters in the list
;;; PARAMETERS-IN-GROUP.  Then it recursively processes the parameters
;;; in REMAINING-PARAMETER-GROUPS in the augmented environment.
;;; Finally, it returns two values.  The first return value is the AST
;;; resulting from the recursive processing and from the processing of
;;; the parameters in PARAMETERS-IN-GROUP and of BODY.  The second
;;; return value is a lexical lambda list corresponding to the
;;; parameters in PARAMETERS-IN-GROUP and in
;;; REMAINING-PARAMETER-GROUPS.
(defgeneric process-parameters-in-group
    (parameters-in-group
     remaining-parameter-groups
     idspecs-in-group
     remaining-idspecs
     entries-in-group
     remaining-entries
     inserter
     environment
     system))

;;; This function first computes a new environment by augmenting
;;; ENVIRONMENT with information from the parameters in
;;; PARAMETER-GROUP.  Then it recursively processes the parameters in
;;; REMAINING-PARAMETER-GROUPS in the augmented environment.  Finally,
;;; it returns two values.  The first return value is the AST
;;; resulting from the recursive processing and from the processing of
;;; the parameters in PARAMETER-GROUP and of BODY.  The second value
;;; is a lexical lambda list that corresponds to the parameters in
;;; PARAMETER-GROUP and REMAINING-PARAMETER-GROUPS.
(defgeneric process-parameter-group
    (parameter-group
     remaining-parameter-groups
     idspecs-in-group
     remaining-idspecs
     entries-in-group
     remaining-entries
     inserter
     environment
     system))

;;; Process all the parameters in the list of parameter groups
;;; PARAMETER-GROUPS.  This function returns a list of parameter groups
;;; that mirror the parameter groups in PARAMETER-GROUPS.
(defgeneric process-parameter-groups
    (parameter-groups
     idspecs
     entries
     inserter
     envrironment
     system))

(defmethod process-parameters-in-group
    ((parameters-in-group null) remaining-parameter-groups
     idspecs-in-group remaining-idspecs
     entries-in-group remaining-entries
     inserter environment system)
  (declare (ignore idspecs-in-group entries-in-group))
  (process-parameter-groups remaining-parameter-groups
                            remaining-idspecs
                            remaining-entries
                            inserter environment system))

(defmethod process-parameters-in-group
    ((parameters-in-group cons) remaining-parameter-groups
     idspecs-in-group remaining-idspecs
     entries-in-group remaining-entries
     inserter environment system)
  (process-parameter (car parameters-in-group) (cdr parameters-in-group)
                     remaining-parameter-groups
                     (car idspecs-in-group) (cdr idspecs-in-group)
                     remaining-idspecs
                     (car entries-in-group) (cdr entries-in-group)
                     remaining-entries
                     inserter environment system))

(defgeneric new-environment-from-parameter
    (parameter idspecs environment system))

(defmethod process-parameter-groups
    ((parameter-groups null) idspecs entries inserter environment system)
  (declare (ignore idspecs entries inserter system))
  environment)

(defmethod process-parameter-groups
    ((parameter-groups cons) idspecs entries inserter environment system)
  (process-parameter-group (car parameter-groups) (cdr parameter-groups)
                           (car idspecs) (cdr idspecs)
                           (car entries) (cdr entries)
                           inserter environment system))

(defmethod process-parameter-group
    ((parameter-group cst:multi-parameter-group-mixin)
     remaining-parameter-groups
     idspecs-in-group remaining-idspecs
     entries-in-group remaining-entries
     inserter environment system)
  (process-parameters-in-group (cst:parameters parameter-group)
                               remaining-parameter-groups
                               idspecs-in-group remaining-idspecs
                               entries-in-group remaining-entries
                               inserter environment system))

(defmethod process-parameter-group
    ((parameter-group cst:ordinary-rest-parameter-group)
     remaining-parameter-groups
     idspecs-in-group remaining-idspecs
     entries-in-group remaining-entries
     inserter environment system)
  (process-parameter (cst:parameter parameter-group) '()
                     remaining-parameter-groups
                     (car idspecs-in-group) '()
                     remaining-idspecs
                     (car entries-in-group) '()
                     remaining-entries
                     inserter environment system))

(defmethod new-environment-from-parameter
    ((parameter cst:simple-variable) idspecs environment system)
  (augment-environment-with-variable (cst:name parameter)
                                     (first idspecs)
                                     system
                                     environment
                                     environment))

(defmethod new-environment-from-parameter
    ((parameter cst:ordinary-key-parameter) idspecs environment system)
  (augment-environment-with-parameter (cst:name parameter)
                                      (cst:supplied-p parameter)
                                      idspecs
                                      environment
                                      system))

(defmethod new-environment-from-parameter
    ((parameter cst:ordinary-optional-parameter) idspecs environment system)
  (augment-environment-with-parameter (cst:name parameter)
                                      (cst:supplied-p parameter)
                                      idspecs
                                      environment
                                      system))

(defmethod new-environment-from-parameter
    ((parameter cst:aux-parameter) idspecs environment system)
  (augment-environment-with-variable (cst:name parameter)
                                     (first idspecs)
                                     system
                                     environment
                                     environment))

(defmethod process-parameter
    ((parameter cst:simple-variable)
     remaining-parameters-in-group
     remaining-parameter-groups
     idspecs remaining-idspecs-in-group remaining-idspecs
     lexical-variable
     remaining-entries-in-group remaining-entries
     inserter environment system)
  (let* ((new-env (new-environment-from-parameter parameter
                                                  idspecs
                                                  environment
                                                  system))
         (var-cst (cst:name parameter))
         (info (env:variable-info system new-env (cst:raw var-cst))))
    (bind-variable var-cst info (list lexical-variable) inserter system)
    (process-parameters-in-group remaining-parameters-in-group
                                 remaining-parameter-groups
                                 remaining-idspecs-in-group remaining-idspecs
                                 remaining-entries-in-group remaining-entries
                                 inserter new-env system)))

(defmethod process-parameter
    ((parameter cst:ordinary-optional-parameter)
     remaining-parameters-in-group
     remaining-parameter-groups
     idspecs remaining-idspecs-in-group remaining-idspecs
     entry remaining-entries-in-group remaining-entries
     inserter environment system)
  (let* ((new-env (new-environment-from-parameter parameter
                                                  idspecs
                                                  environment system))
         (var-cst (cst:name parameter))
         (supplied-p-cst (cst:supplied-p parameter))
         (init-form-cst (if (null (cst:form parameter))
                            (make-atom-cst nil (cst:source var-cst))
                            (cst:form parameter))))
    (process-init-parameter
     var-cst (first entry)
     supplied-p-cst (second entry)
     init-form-cst inserter new-env system)
    (process-parameters-in-group remaining-parameters-in-group
                                 remaining-parameter-groups
                                 remaining-idspecs-in-group remaining-idspecs
                                 remaining-entries-in-group remaining-entries
                                 inserter new-env system)))

(defmethod process-parameter
    ((parameter cst:ordinary-key-parameter)
     remaining-parameters-in-group
     remaining-parameter-groups
     idspecs remaining-idspecs-in-group remaining-idspecs
     entry remaining-entries-in-group remaining-entries
     inserter environment system)
  (let* ((new-env (new-environment-from-parameter parameter
                                                  idspecs
                                                  environment system))
         (var-cst (cst:name parameter))
         (supplied-p-cst (cst:supplied-p parameter))
         (init-form-cst (if (null (cst:form parameter))
                            (make-atom-cst nil (cst:source var-cst))
                            (cst:form parameter))))
    (process-init-parameter
     var-cst (first entry)
     supplied-p-cst (second entry)
     init-form-cst inserter environment system)
    (process-parameters-in-group remaining-parameters-in-group
                                 remaining-parameter-groups
                                 remaining-idspecs-in-group remaining-idspecs
                                 remaining-entries-in-group remaining-entries
                                 inserter new-env system)))

(defmethod process-parameter
    ((parameter cst:aux-parameter)
     remaining-parameters-in-group
     remaining-parameter-groups
     idspecs remaining-idspecs-in-group remaining-idspecs
     entry remaining-entries-in-group remaining-entries
     inserter environment system)
  (declare (ignore entry))
  (let* ((var-cst (cst:name parameter))
         (init-form-cst (cst:form parameter))
         (new-env (new-environment-from-parameter parameter
                                                  idspecs
                                                  environment
                                                  system))
         (var-info (env:variable-info system new-env (cst:raw var-cst)))
         (vals (convert init-form-cst inserter environment system)))
    (bind-variable var-cst var-info vals inserter system)
    (process-parameters-in-group remaining-parameters-in-group
                                 remaining-parameter-groups
                                 remaining-idspecs-in-group
                                 remaining-idspecs
                                 remaining-entries-in-group
                                 remaining-entries
                                 inserter new-env system)))

(defun itemize-declaration-specifiers-by-parameter-group
    (items-by-parameter-group canonical-dspecs)
  (if (null items-by-parameter-group)
      (values '() canonical-dspecs)
      (multiple-value-bind (itemized-dspecs remaining-dspecs)
           (itemize-declaration-specifiers (first items-by-parameter-group)
                                           canonical-dspecs)
        (multiple-value-bind (more-itemized-dspecs more-remaining-dspecs)
            (itemize-declaration-specifiers-by-parameter-group
             (rest items-by-parameter-group)
             remaining-dspecs)
          (values (cons itemized-dspecs more-itemized-dspecs)
                  more-remaining-dspecs)))))

(defun cst-for-body (forms-cst block-name-cst &optional origin)
  (if block-name-cst
      (cst:quasiquote origin (block (cst:unquote block-name-cst)
                               (cst:unquote-splicing forms-cst)))
      (cst:quasiquote origin (progn (cst:unquote-splicing forms-cst)))))

;;; Given the entries and idspecs, compute and return an alist from LEXICAL-VARIABLEs
;;; to lists of declaration specifier CSTs for that lexical variable.
(defun compute-bound-declarations (entries idspecs)
  ;; NOTE: We use raw declaration specifiers so that ASTs can be serialized
  ;; without CSTs having to be serializable, but we might want to decide
  ;; otherwise later?
  (loop for vargroup in entries for specgroup in idspecs
        append (loop for variables in vargroup
                     for specses in specgroup
                     append (loop for variable
                                    in (if (listp variables)
                                           variables
                                           (list variables))
                                  for specs in specses
                                  unless (null specs)
                                    collect (cons variable
                                                  (mapcar #'cst:raw specs))))))

(defmethod convert-code (lambda-list-cst body-cst env system
                         &key (block-name-cst nil) (origin bir:*origin*)
                           name)
  (let ((parsed-lambda-list
          (cst:parse-ordinary-lambda-list system lambda-list-cst :error-p nil)))
    (when (null parsed-lambda-list)
      (error 'malformed-lambda-list :cst lambda-list-cst))
    (multiple-value-bind (declaration-csts documentation forms-cst)
        (cst:separate-function-body body-cst)
      (let* ((declaration-specifiers
               (loop for declaration-cst in declaration-csts
                     append (cdr (cst:listify declaration-cst))))
             (canonicalized-dspecs
               (cst:canonicalize-declaration-specifiers
                system (env:declarations env) declaration-specifiers))
             (itemized-lambda-list
               (itemize-lambda-list parsed-lambda-list)))
        (multiple-value-bind (idspecs rdspecs)
            (itemize-declaration-specifiers-by-parameter-group
             itemized-lambda-list canonicalized-dspecs)
          (multiple-value-bind (lexical-lambda-list entries)
              (lambda-list-from-parameter-groups
               (cst:children parsed-lambda-list))
            (let* ((module *current-module*)
                   (function (make-instance 'bir:function
                               :name name
                               :docstring (when documentation
                                            (cst:raw documentation))
                               :lambda-list lexical-lambda-list
                               :original-lambda-list (cst:raw lambda-list-cst)
                               :origin origin
                               :policy bir:*policy*
                               :module module))
                   (inserter (make-instance 'inserter))
                   (start (make-iblock inserter
                                       :name (symbolicate (write-to-string name)
                                                          '#:-start)
                                       :function function
                                       :dynamic-environment function))
                   (bound-declarations
                     (compute-bound-declarations entries idspecs)))
              (declare (ignore bound-declarations)) ; FIXME
              (set:nadjoinf (bir:functions module) function)
              (setf (bir:start function) start)
              (begin inserter start)
              (let* ((bindings-env
                       (process-parameter-groups
                        (cst:children parsed-lambda-list)
                        idspecs entries inserter env system))
                     (body-env
                       (augment-environment-with-declarations bindings-env
                                                              system
                                                              rdspecs))
                     (rv
                      (convert (cst-for-body forms-cst block-name-cst origin)
                               inserter body-env system)))
                (if (eq rv :no-return)
                    (setf (bir:returni function) nil)
                    (let ((returni (make-instance 'bir:returni :inputs rv)))
                      (setf (bir:returni function) returni)
                      (terminate inserter returni))))
              (bir:compute-iblock-flow-order function)
              function)))))))

(defmethod convert-function (lambda-list-cst body-cst inserter env system
                             &key (block-name-cst nil) origin name)
  (let* ((f (convert-code lambda-list-cst body-cst env system
                          :block-name-cst block-name-cst
                          :origin origin :name name))
         (enclose-out (make-instance 'bir:output :name name))
         (enclose (make-instance 'bir:enclose
                    :code f :outputs (list enclose-out))))
    (setf (bir:enclose f) enclose)
    (insert inserter enclose)
    (list enclose-out)))
