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
  ;; the zone by its tzdata name, which gives the offset, one hour east of
  ;; Greenwich, and the rule for summer time (SYS: IO1; TIME and TZDATA).
  ;; a number here is a fixed offset in hours west, with no summer time.
  (:timezone "Europe//Berlin")
  ;; OZ is this site's Chaos file, time and host-table server, used only
  ;; when named: SYS: and the associated machine are HOST, the file device
  ;; (SYS: SITE; SYS TRANSLATIONS, LMLOCS), and the time comes from QUUX's
  ;; real-time clock.
  (:CHAOS-FILE-SERVER-HOSTS '("OZ"))
  (:CHAOS-TIME-SERVER-HOSTS '("OZ"))
  (:CHAOS-HOST-TABLE-SERVER-HOSTS '("OZ"))
  ;; Compiler warnings go beside the patches
  (:WARNINGS-PATHNAME-DEFAULT "SYS: PATCH;")
  )
