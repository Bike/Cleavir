(cl:in-package #:common-lisp-user)

(defpackage #:cleavir-bir
  (:use #:cl)
  (:shadow #:function #:catch #:set #:variable #:load-time-value #:case
           #:disassemble)
  (:export #:function #:iblocks #:start #:end #:inputs #:variables
           #:lambda-list)
  (:export #:dynamic-environment #:scope #:parent #:lexical-bind #:bindings)
  (:export #:iblock #:predecessors #:entrances #:exits #:iblock-started-p)
  (:export #:rtype #:rtype=)
  (:export #:datum #:ssa #:value #:linear-datum #:transfer #:argument #:phi
           #:output #:name
           #:definitions #:uses #:definition #:use)
  (:export #:variable #:extent #:owner #:writers #:readers #:encloses #:binder)
  (:export #:constant #:make-constant #:immediate #:load-time-value
           #:constant-value #:immediate-value #:form #:read-only-p)
  (:export #:instruction #:operation #:computation #:inputs #:outputs
           #:terminator #:terminator0 #:terminator1
           #:successor #:predecessor #:next
           #:origin #:policy)
  (:export #:*origin* #:*policy*)
  (:export #:multiple-to-fixed #:fixed-to-multiple
           #:accessvar #:writevar #:readvar #:cast
           #:returni #:unreachable #:eqi #:jump #:unwindp
           #:typeq #:type-specifier #:typew #:ctype #:choke
           #:case #:comparees
           #:catch #:unwinds #:unwind #:destination
           #:alloca #:writetemp #:readtemp
           #:leti #:call #:enclose #:code)
  (:export #:primop-info #:in-rtypes
           #:primop #:vprimop #:nvprimop)
  (:export #:map-instructions #:map-instructions-with-owner-from-set
           #:map-iblocks #:all-functions
           #:insert-instruction-before #:insert-instruction-after
           #:replace-computation #:delete-computation #:delete-instruction
           #:replace-uses #:replace-terminator #:split-block-after
           #:move-inputs #:delete-iblock)
  (:export #:refresh-iblocks #:refresh-local-iblocks
           #:refresh-users #:refresh-local-users)
  (:export #:verify)
  (:export #:disassemble))
