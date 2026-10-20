;;; -*- Mode:LISP; Package:USER; Base:10; Readtable:ZL -*-
;;; For the check machine-name (tools/system-check/machine-name, README.md):
;;; the machine's name after step R3 of QUUX's Ethernet contract (section 5.6,
;;; "From R3"): the name file, SET-HOST-NAME's name, the INTERNET match, else
;;; LOCALHOST.  Typed at the console, since revision 15's band has no network
;;; for a session; each answer goes to a file in the login's home directory
;;; (the file device's /home/lispm/, on HOST or FILES as the band names it),
;;; which the harness reads.

(defun mn-facts ()
  "(the host's name, SI:LOCAL-HOST-NAME, the pretty name, the associated machine's name,
the name the herald gives after /"band N of/")"
  ;; N is the band booted: 1 from the disk, 2 from the save into LOD2.
  (let* ((herald (si:print-loaded-band nil))
	 (band (string-search "band " herald))
	 (at (and band (string-search " of " herald band)))
	 (end (and at (string-search "," herald at))))
    (list (send si:local-host :name) si:local-host-name si:local-pretty-host-name
	  (send si:associated-machine :name)
	  (and at (substring herald (+ at 4) end)))))

(defun mn-write (tag &optional (facts (mn-facts)))
  "Write FACTS to mn-TAG.text in the login's home directory, for the harness."
  ;; the home, not a named host, so that a band naming the file device's host
  ;; HOST or FILES writes alike; the file was HOST's, which a FILES band misparses:
  ;;   (with-open-file (s (string-append "HOST: //home//lispm//mn-" (string-downcase tag) ".text")
  ;;                   :direction :output)
  (with-open-file (s (fs:merge-pathname-defaults
		       (string-append "mn-" (string-downcase tag) ".text") (fs:user-homedir))
		     :direction :output)
    (let ((*print-base* 10.)) (prin1 facts s)))
  facts)

(defun mn-internet (tag)
  "On revision 16: a site entry, TEST-INTERNET, whose INTERNET address is the device's;
the machine's name found again (with no name file and no SET-HOST-NAME, the INTERNET match
wins over LOCALHOST); then MN-WRITE."
  (si:define-host "TEST-INTERNET" :host-names '("TEST-INTERNET") :system-type :lispm
		  :machine-type :cadr :internet (list (ip::address-string (ip::ether-register ip::%ether-ip-address))))
  (si:set-local-host)
  (si:set-local-host-variables)
  (mn-write tag))
