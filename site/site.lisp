;;;-*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8 -*-
;;; Site declaration for MIT
;;; The name is MIT's own, as System 100 has it, so PRINT-HERALD says
;;; "MIT System" and the band identifies itself as a System 100 band did.
;;; Only the name is taken: the hosts, the subnet and the timezone below
;;; are this machine's.

(DEFSITE :MIT
  ;; How to log in to get system files
  (:SYS-LOGIN-NAME "LISPM")
  (:SYS-LOGIN-PASSWORD "LISPM")
  ;; CET: one hour east of Greenwich
  (:TIMEZONE -1)
  ;; OZ is the associated machine: files, time and host table
  (:CHAOS-FILE-SERVER-HOSTS '("OZ"))
  (:CHAOS-TIME-SERVER-HOSTS '("OZ"))
  (:CHAOS-HOST-TABLE-SERVER-HOSTS '("OZ"))
  ;; Compiler warnings go beside the patches
  (:WARNINGS-PATHNAME-DEFAULT "SYS: PATCH;")
  )
