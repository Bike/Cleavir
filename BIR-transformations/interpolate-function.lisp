(in-package #:cleavir-bir-transformations)

(defun replace-unwind (u)
  (let ((unwind-inputs (cleavir-bir:inputs u))
        (unwind-outputs (cleavir-bir:outputs u))
        (new (make-instance 'cleavir-bir:jump
               :next (list (cleavir-bir:destination u)))))
    (cleavir-bir:replace-terminator new u)
    (setf (cleavir-bir:inputs new) unwind-inputs
          (cleavir-bir:outputs new) unwind-outputs))
  (let ((catch (cleavir-bir:catch u)))
    (when (catch-eliminable-p catch)
      (eliminate-catch catch))))

;;; interpolated-function must have only required parameters
(defun interpolate-function (interpolated-function call)
  (let* ((lambda-list (cleavir-bir:lambda-list interpolated-function))
         (call-block (cleavir-bir:iblock call))
         (call-function (cleavir-bir:function call-block))
         (interp-end (cleavir-bir:end interpolated-function))
         (returni (when interp-end (cleavir-bir:end interp-end)))
         (return-values (when interp-end (first (cleavir-bir:inputs returni))))
         (arguments (rest (cleavir-bir:inputs call))))
    (check-type call cleavir-bir:local-call)
    (assert (every (lambda (a) (typep a 'cleavir-bir:argument)) lambda-list))
    ;; Rewire control
    (multiple-value-bind (before after)
        (cleavir-bir:split-block-after call)
      ;; BEFORE is now a block that jumps with no arguments to
      ;; AFTER.
      (cleavir-bir:replace-terminator
       (make-instance 'cleavir-bir:jump
                      :next (list (cleavir-bir:start interpolated-function))
                      :inputs () :outputs ())
       (cleavir-bir:end before))
      (cleavir-set:nunionf (cleavir-bir:variables call-function)
                           (cleavir-bir:variables interpolated-function))
      (cleavir-set:nunionf (cleavir-bir:catches call-function)
                           (cleavir-bir:catches interpolated-function))
      ;; Replace the return instruction with a jump if there is one, or else
      ;; delete AFTER and any later straight line blocks.
      (if interp-end
          (cleavir-bir:replace-terminator
           (make-instance 'cleavir-bir:jump
             :inputs () :outputs ()
             :next (list after))
           returni)
          (cleavir-bir:maybe-delete-iblock after))
      ;; If the interpolated function unwinds to the call function, change it
      ;; to a local unwind.
      (cleavir-set:doset (ib (cleavir-bir:exits interpolated-function))
        (let ((u (cleavir-bir:end ib)))
          (check-type u cleavir-bir:unwind)
          (let ((dest (cleavir-bir:destination u)))
            (when (eq (cleavir-bir:function dest) call-function)
              (replace-unwind u)))))
      ;; Re-home iblocks (and indirectly, instructions)
      (cleavir-bir:map-iblocks
       (lambda (ib)
         (when (eq (cleavir-bir:dynamic-environment ib) interpolated-function)
           (setf (cleavir-bir:dynamic-environment ib)
                 (cleavir-bir:dynamic-environment before)))
         (setf (cleavir-bir:function ib) call-function)
         (cleavir-set:nadjoinf (cleavir-bir:iblocks call-function) ib))
       interpolated-function)
      ;; The interpolated function no longer owns these blocks. Need
      ;; to do this so we don't accidentally clean them up.
      (setf (cleavir-bir:iblocks interpolated-function) (cleavir-set:empty-set))
      (cond (return-values
             (let ((call-use (unless (cleavir-bir:unused-p call)
                               (cleavir-bir:use call))))
               ;; Replace the call-as-datum with the return-values.
               (cleavir-bir:replace-computation call return-values)
               ;; If we have a FTM->MTF sequence, clear it out.
               (when (and call-use
                          (typep return-values 'cleavir-bir:fixed-to-multiple)
                          (typep call-use 'cleavir-bir:multiple-to-fixed))
                 (cleavir-bir:delete-transmission return-values call-use))))
            (t
             ;; The call isn't used, so simply delete it.
             (cleavir-bir:delete-computation call)))
      ;; Replace the arguments in the interpolated function body with the
      ;; actual argument values
      (mapc #'cleavir-bir:replace-uses arguments lambda-list)
      ;; Merge the blocks. Merge the tail first since the
      ;; interpolated function might just be one block.
      (if interp-end
          (cleavir-bir:merge-successor-if-possible interp-end)
          ;; The function doesn't return, so make sure later blocks are deleted
          (cleavir-bir:refresh-local-iblocks call-function))
      (cleavir-bir:merge-successor-if-possible before)))
  (values))
