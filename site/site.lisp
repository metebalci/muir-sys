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
  ;; when named: SYS: and the associated machine are FILES, the file device
  ;; (SYS: SITE; SYS TRANSLATIONS, LMLOCS), and the time comes from QUUX's
  ;; real-time clock.
  ;; quux revision 16 (QUUX's Ethernet contract, section 8, step R3): the NCP
  ;; and the QFILE client left the band, so OZ can serve nothing and is no
  ;; longer made a file host; the builder's files come from FILES: too.
;  (:CHAOS-FILE-SERVER-HOSTS '("OZ"))
;  (:CHAOS-TIME-SERVER-HOSTS '("OZ"))
;  (:CHAOS-HOST-TABLE-SERVER-HOSTS '("OZ"))
  ;; quux revision 16 (QUUX's Ethernet contract, sections 5.6 and 8, step R3):
  ;; with the NCP gone a machine is an unnamed host, which LMLOCS cannot name,
  ;; so the associated machine of every machine is FILES here too, as LMLOCS
  ;; gives it for LISPM-1 to LISPM-7 (else it was the first pathname host).
  ;; it was HOST, the file device's name before it became FILES:
;  (:default-associated-machine "HOST")
  (:default-associated-machine "FILES")
  ;; Compiler warnings go beside the patches
  (:WARNINGS-PATHNAME-DEFAULT "SYS: PATCH;")
  )
