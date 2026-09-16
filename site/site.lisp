;;;-*- Mode:LISP; Package:SYSTEM-INTERNALS; Base:8 -*-
;;; Site declaration for Z54

(DEFSITE :Z54
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
