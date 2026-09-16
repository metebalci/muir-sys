;;; -*- Mode:Lisp;Package:NETI;Base:10; Readtable: T -*-
;;; This is SYS: NETWORK; SMTP
;;; Network independent frobs for SMTP


(DEFUN SMTP-STUFF-TEXT (MESSAGE STREAM)
  "Send MESSAGE over STREAM, using <NL>.<NL> at the end.
Doesn't do a force output on STREAM when done."
  (WITH-INPUT-FROM-STRING (M MESSAGE)
    (DO ((LINE) (EOF))
	(EOF (SEND STREAM :LINE-OUT "."))
      (MULTIPLE-VALUE (LINE EOF) (SEND M :LINE-IN))
      (AND (NOT (ZEROP (STRING-LENGTH LINE)))
	   (CHAR-EQUAL (AREF LINE 0) #/.)
	   (SEND STREAM :TYO #/.))
      (SEND STREAM :LINE-OUT LINE))))

(DEFUN GOBBLE-RESP-LINE (STREAM)
  (DO ((LINE (SEND STREAM :LINE-IN) (SEND STREAM :LINE-IN)))
      ((NOT (CHAR-EQUAL #/- (AREF LINE 3))) LINE)))
  
(DEFMACRO PROT-RESP-EQUAL (CODE R-VAR S-VAR)
  `(PROGN :COMPILE
	  (SEND ,S-VAR :FORCE-OUTPUT)
	  (SETQ ,R-VAR (GOBBLE-RESP-LINE ,S-VAR))
	  (STRING-EQUAL ,CODE ,R-VAR :END1 3 :END2 3)))

(DEFUN HANDLE-SMTP-SEND (STREAM PERSON MESSAGE FROM &OPTIONAL GW &AUX RESP (FINAL T))
  "Send in an interactive message to PERSON.
STREAM should be a net stream connected to the correct host at an SMTP socket.
The message should just be a body of text.  GW is for ``indirect'' routing.
Closes the stream.
Returns T if sent, otherwise an error instance (net problems) or () (can't send)"
  (UNWIND-PROTECT
      (TAGBODY
	  ;; Greetings -- discard first blank line (some hosts send it)
	  (GOBBLE-RESP-LINE STREAM)
	  ;; HELO
	  (SEND STREAM :STRING-OUT "HELO ")
	  (SEND STREAM :STRING-OUT (STRING (OR GW SI:LOCAL-HOST)))
	  (SEND STREAM :LINE-OUT  ".ARPA")
	  (IF (NOT (PROT-RESP-EQUAL "250" RESP STREAM)) (GO .LOSE))
	  ;; We want a SEND
	  (SEND STREAM :STRING-OUT "SEND FROM:<")
	  (SEND STREAM :STRING-OUT FROM)
	  (SEND STREAM :LINE-OUT ">")
	  (IF (NOT (PROT-RESP-EQUAL "250" RESP STREAM)) (GO .LOSE))
	  ;; Make the recipient known
	  (SEND STREAM :STRING-OUT "RCPT TO:<")
	  (SEND STREAM :STRING-OUT PERSON) ; is this too simple ?
	  (SEND STREAM :LINE-OUT ">")
	  (IF (NOT (PROT-RESP-EQUAL "250" RESP STREAM)) (GO .LOSE))
	  ;; He's there; let's send the message
	  (SEND STREAM :LINE-OUT "DATA")
	  (IF (NOT (PROT-RESP-EQUAL "354" RESP STREAM)) (GO .LOSE))
	  ;; Go for it
	  (SMTP-STUFF-TEXT MESSAGE STREAM)
	  (IF (NOT (PROT-RESP-EQUAL "250" RESP STREAM)) (GO .LOSE))
	  (GO .CLOSE)
	  .LOSE ; protocol lossage goes here
	  (SETQ FINAL ())
	  .CLOSE
	  ;; Well, fine !
	  (SEND STREAM :LINE-OUT "QUIT")
	  (SEND STREAM :FORCE-OUTPUT)
	  ;; second value should be a lusing error message
	  (IF FINAL
	      (SETQ RESP (SEND STREAM :LINE-IN))
	    (SEND STREAM :LINE-IN))) ; just read it....
    (SEND STREAM :CLOSE T))
  (VALUES FINAL RESP))
