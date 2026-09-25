;;; Date and time routines -*- Mode:LISP; Package:TIME; Readtable:T; Base:10 -*-
;;;	** (c) Copyright 1980 Massachusetts Institute of Technology **

;;; Note: days and months are kept one-based throughout, as much as possible.
;;; Days of the week are zero-based on Monday.

;;; [Maybe this should have a global variable which causes it to use AM/PM in place
;;;  of 24-hour time, in all relevant functions?]
;; this should probably have variable which is the initial-year, 
;; in case we want more precision.


(DEFINE-SITE-VARIABLE *TIMEZONE* :TIMEZONE "The timezone.")

;; these should probably be site variables too
(DEFVAR *DAYLIGHT-SAVINGS-TIME-P-FUNCTION* 'DAYLIGHT-SAVINGS-TIME-IN-NORTH-AMERICA-P
  "A function, which when applied to arguments of seconds minutes hours day month year,
will return T if daylight savings time is in effect in the local timezonew at that time.")

(DEFVAR *DEFAULT-DATE-PRINT-MODE* :MM//DD//YY	;perhaps site variable?
  "Defines the default way to print the date. Possible values include:
:DD//MM//YY :MM//DD//YY :DD-MM-YY :DD-MMM-YY :|DD MMM YY| :DDMMMYY :YYMMDD :YYMMMDD
 and similar keywords with YYYY instead of YY.")

(DEFUN MICROSECOND-TIME (&AUX (INHIBIT-SCHEDULING-FLAG T))
  "Return the current value of the microsecond clock (a bignum).
Only differences in clock values are meaningful.
There are 32. bits of data, so the value wraps around every few hours."
  ;; quux: the processor's clock, source 15, read by fields; a field is one
  ;; read.  %microsecond-clock-ldb is in global (cold/global.lisp).
  ;; read, so the high half is read on both sides of the low and the pair is
  ;; taken when they agree.  the cadr's unibus clock latched the high half
  ;; when the low was read.
  (do () (nil)
    (let* ((high (%microsecond-clock-ldb #o2020))
	   (low (%microsecond-clock-ldb #o0020)))
      (when (= high (%microsecond-clock-ldb #o2020))
	(return (dpb high #o2020 low))))))

(DEFUN FIXNUM-MICROSECOND-TIME (&AUX (INHIBIT-SCHEDULING-FLAG T))
  "Return the current value of the microsecond clock as two fixnums."
  (DECLARE (VALUES LOW-23-BITS TOP-9-BITS))
  ;; quux: the processor's clock, source 15, as in microsecond-time.
  (do () (nil)
    (let* ((high (%microsecond-clock-ldb #o2711))
	   (low (%microsecond-clock-ldb #o0027)))
      (when (= high (%microsecond-clock-ldb #o2711))
	(return (values low high))))))

(DEFCONST INTERNAL-TIME-UNITS-PER-SECOND 60.
  "60 60ths of a second in a second.")

(DEFVAR HIGH-TIME-BITS 0
  "Number of times (TIME) has wrapped around since booting.")

(DEFVAR WAS-NEGATIVE NIL
  "T if (TIME) was TIME-LESSP than LAST-BOOT-TIME when last checked.
Each this changes from T to NIL, (TIME) has wrapped around once.")

(DEFVAR LAST-BOOT-TIME 0 "Value of (TIME) when machine was booted.")

(DEFF GET-INTERNAL-REAL-TIME 'GET-INTERNAL-RUN-TIME)
(DEFUN GET-INTERNAL-RUN-TIME ()
  "Returns time in 60'ths since last boot. May be a bignum."
  (LET ((TIME-DIFF (%POINTER-DIFFERENCE (TIME) LAST-BOOT-TIME)))
    (WHEN (AND (PROG1 WAS-NEGATIVE
		      (SETQ WAS-NEGATIVE (LDB-TEST (BYTE 1 22.) TIME-DIFF)))
	       (NOT WAS-NEGATIVE))
      (INCF HIGH-TIME-BITS))
    (DPB HIGH-TIME-BITS (BYTE 23. 23.) (LDB (BYTE 23. 0) TIME-DIFF))))


;;;; Conversion routines, universal time is seconds since 1-jan-00 00:00-GMT

(DEFVAR *CUMULATIVE-MONTH-DAYS-TABLE*
	(MAKE-ARRAY 13. :TYPE 'ART-16B
		        :INITIAL-CONTENTS '#10r(0 0   31  59  90  120 151
						  181 212 243 273 304 334))
  "One-based array of cumulative days per month.")

;;; Takes Univeral Time (seconds since 1/1/1900) as a 32-bit number
;;; Algorithm from KLH's TIMRTS.
(DEFUN DECODE-UNIVERSAL-TIME (UNIVERSAL-TIME &OPTIONAL TIMEZONE
					     &AUX SECS MINUTES HOURS DAY MONTH YEAR
						  DAY-OF-THE-WEEK DAYLIGHT-SAVINGS-TIME-P)
  "Given a UNIVERSAL-TIME, decode it into year, month number, day of month, etc.
TIMEZONE is hours before GMT (5, for EST).
DAY and MONTH are origin-1.  DAY-OF-THE-WEEK = 0 for Monday."
  (DECLARE (VALUES SECS MINUTES HOURS DAY MONTH YEAR
		   DAY-OF-THE-WEEK DAYLIGHT-SAVINGS-TIME-P TIMEZONE))
  (IF TIMEZONE					;explicit timezone means no-dst
      (MULTIPLE-VALUE (SECS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK)
	 (DECODE-UNIVERSAL-TIME-WITHOUT-DST UNIVERSAL-TIME TIMEZONE))
    ;;Otherwise, decode the time and THEN daylight-adjust it.
    (MULTIPLE-VALUE (SECS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK)
      (DECODE-UNIVERSAL-TIME-WITHOUT-DST UNIVERSAL-TIME *TIMEZONE*))
    (AND (SETQ DAYLIGHT-SAVINGS-TIME-P
	       (FUNCALL *DAYLIGHT-SAVINGS-TIME-P-FUNCTION*
			SECS MINUTES HOURS DAY MONTH YEAR))
	 ;; See if it's daylight savings time, time-zone number gets smaller if so.
	 (MULTIPLE-VALUE (SECS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK)
	   (DECODE-UNIVERSAL-TIME-WITHOUT-DST UNIVERSAL-TIME (1- *TIMEZONE*)))))
  (VALUES SECS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK DAYLIGHT-SAVINGS-TIME-P
	  (OR TIMEZONE *TIMEZONE*)))

(DEFUN DECODE-UNIVERSAL-TIME-WITHOUT-DST (UNIVERSAL-TIME &OPTIONAL (TIMEZONE *TIMEZONE*)
					  &AUX X SECS MINUTES HOURS DAY MONTH YEAR)
  "Like DECODE-UNIVERSAL-TIME, but always uses standard time.
Even if the time is one at which daylight savings time would be in effect,
the hour and date are computed as for standard time."
  (DECLARE (VALUES SECS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK TIMEZONE))
  (SETQ UNIVERSAL-TIME (- UNIVERSAL-TIME (* TIMEZONE 3600.)))
  (SETQ SECS (\ UNIVERSAL-TIME (* 24. 60. 60.))
	X (TRUNCATE UNIVERSAL-TIME (* 24. 60. 60.)))	;Days since genesis.
  ;; the date from the day count by Howard Hinnant's civil_from_days
  ;; (howardhinnant.github.io/date_algorithms.html), in 400-year eras that
  ;; begin on 1 march, so that a leap day ends its year.  KLH's algorithm
  ;; here took every fourth year for a leap year, 1900 and 2100 too: for the
  ;; rest of 1900 from 1 march, and from 1 march 2100 on, it gave the day
  ;; before (1 march as 29 february), and at the real-time clock's last
  ;; second (2^32-1, 7 february 2106) the 6th.  day 0, 1 january 1900, is
  ;; day 693901 counted from 1 march of the year 0.
  (let* ((z (+ x 693901.))
	 (era (floor z 146097.))
	 (doe (- z (* era 146097.)))		;day of the era, 0 to 146096
	 (yoe (floor (- (+ doe (floor doe 36524.)) (floor doe 1460.) (floor doe 146096.))
		     365.))				;year of the era, 0 to 399
	 (doy (- doe (* 365. yoe) (floor yoe 4) (- (floor yoe 100.))))	;from 1 march, 0 to 365
	 (mp (floor (+ (* 5 doy) 2) 153.)))	;month from march, 0 to 11
    (setq day (1+ (- doy (floor (+ (* 153. mp) 2) 5)))
	  month (if (< mp 10.) (+ mp 3) (- mp 9.))
	  year (+ yoe (* era 400.) (if (<= month 2) 1 0))))
  (SETQ HOURS (FLOOR SECS 3600.)
	MINUTES (FLOOR (\ SECS 3600.) 60.)
	SECS (\ SECS 60.))
  (VALUES SECS MINUTES HOURS DAY MONTH YEAR (\ X 7) TIMEZONE))

(DEFUN DAYLIGHT-SAVINGS-TIME-P (&REST ARGS)
  "T if daylight savings time would be in effect at specified time in the local timezone."
  (DECLARE (ARGLIST HOURS DAY MONTH YEAR))
  (APPLY *DAYLIGHT-SAVINGS-TIME-P-FUNCTION* 0 0 ARGS))

(DEFUN YYYY-YY (YEAR CURRENT-YEAR)
  (IF (= (TRUNCATE (+ YEAR 50.) 100.) (TRUNCATE (+ CURRENT-YEAR 50.) 100.))
      (MOD YEAR 100.)
    YEAR))

 (DEFUN ENCODE-UNIVERSAL-TIME (SECONDS MINUTES HOURS DAY MONTH YEAR
			      &OPTIONAL TIMEZONE &AUX TEM)
  "Given a time, return a universal-time encoding of it.
A universal-time is the number of seconds since 1-Jan-1900 00:00-GMT (a bignum)."
  (IF (< YEAR 100.)
      (LET ((CURRENT-YEAR (NTH-VALUE 5 (GET-DECODED-TIME))))
	;; In case called during startup or during DISK-SAVE.
	(UNLESS CURRENT-YEAR
	  (SETQ CURRENT-YEAR 2000.))
	(SETQ YEAR
	      (+ CURRENT-YEAR
		 (- (MOD (+ 50. (- YEAR (\ CURRENT-YEAR 100.))) 100.) 50.)))))
  (SETQ YEAR (- YEAR 1900.))
  (OR TIMEZONE
      (SETQ TIMEZONE (IF (DAYLIGHT-SAVINGS-TIME-P HOURS DAY MONTH YEAR)
			 (1- *TIMEZONE*) *TIMEZONE*)))
  ;; the leap days from 1900 to the year before, by the gregorian rule (460
  ;; of them up to 1899), and the year's own after february.  this counted
  ;; every fourth year, 2100 too, so from 2101 on it came out a day late; it
  ;; counted one before 1900 (FLOOR of -1), a day early all through 1900; and
  ;; it asked LEAP-YEAR-P about the year less 1900, 100 for 2000, which said
  ;; no, so 2000's dates from march came out a day early.
  (let ((y (+ year 1899.)))
    (setq tem (+ (1- day) (aref *cumulative-month-days-table* month) (* year 365.)
		 (floor y 4) (- (floor y 100.)) (floor y 400.) -460.)))
  (and (> month 2) (leap-year-p (+ year 1900.))
       (setq tem (1+ tem)))				;after 29 february in a leap year.
  (+ SECONDS (* 60. MINUTES) (* 3600. HOURS) (* TEM (* 60. 60. 24.)) (* TIMEZONE 3600.)))


;;;; domain-dependent knowledge
(DEFUN DAYLIGHT-SAVINGS-TIME-IN-NORTH-AMERICA-P (SECONDS MINUTES HOURS DAY MONTH YEAR)
  "T if daylight savings time would be in effect at specified time in North America."
  (DECLARE (IGNORE SECONDS MINUTES))
  (COND ((OR (< MONTH 4)		;Standard time if before 2 am last Sunday in April
	     (AND (= MONTH 4)
		  (LET ((LSA (LAST-SUNDAY-IN-APRIL YEAR)))
		    (OR (< DAY LSA)
			(AND (= DAY LSA) (< HOURS 2))))))
	 NIL)
	((OR (> MONTH 10.)		;Standard time if after 1 am last Sunday in October
	     (AND (= MONTH 10.)
		  (LET ((LSO (LAST-SUNDAY-IN-OCTOBER YEAR)))
		    (OR (> DAY LSO)
			(AND (= DAY LSO) ( HOURS 1))))))
	 NIL)
	(T T)))

(DEFUN LAST-SUNDAY-IN-OCTOBER (YEAR)
  (LET ((LSA (LAST-SUNDAY-IN-APRIL YEAR)))
    ;; Days between April and October = 31+30+31+31+30 = 153  6 mod 7
    ;; Therefore the last Sunday in October is one less than the last Sunday in April
    ;; unless that gives 24. or 23. in which case it is six greater.
    (IF ( LSA 25.) (+ LSA 6) (1- LSA))))

(DEFUN LAST-SUNDAY-IN-APRIL (YEAR)
  (IF (> YEAR 100.)
      (SETQ YEAR (- YEAR 1900.)))
  ;; This copied from GDWOBY routine in ITS
  (LET ((DOW-BEG-YEAR
	  (LET ((B (\ (+ YEAR 1899.) 400.)))
	    (\ (- (+ (1+ B) (SETQ B (FLOOR B 4))) (FLOOR B 25.)) 7)))
	(FEB29 (IF (LEAP-YEAR-P YEAR) 1 0)))
    (LET ((DOW-APRIL-30 (\ (+ DOW-BEG-YEAR 119. FEB29) 7)))
      (- 30. DOW-APRIL-30))))

;;;; Maintenance functions

(DEFVAR *LAST-TIME-UPDATE-TIME* NIL
  "A number representing the universal time of the last update time.")
(DEFVAR PREVIOUS-TOP-9-TIME-BITS NIL)
(DEFVAR *LAST-TIME-SECONDS* NIL "A number representing the seconds of the last update time.")
(DEFVAR *LAST-TIME-MINUTES* NIL "A number representing the minutes of the last update time.")
(DEFVAR *LAST-TIME-HOURS* NIL "A number representing the hours of the last update time.")
(DEFVAR *LAST-TIME-DAY* NIL "A number representing the day of the last update time.")
(DEFVAR *LAST-TIME-MONTH* NIL "A number representing the month of the last update time.")
(DEFVAR *LAST-TIME-YEAR* NIL "A number representing the year of the last update time.")
(DEFVAR *LAST-TIME-DAY-OF-THE-WEEK* NIL
  "A number representing the day of the week of the last update time.")
(DEFVAR *LAST-TIME-DAYLIGHT-SAVINGS-P* NIL "Whether it was DST the last update time.")
(DEFVAR *NETWORK-TIME-FUNCTION* NIL)
(DEFVAR *UT-AT-BOOT-TIME* NIL "Used for UPTIME protocol, do not random SETQ.")

;; quux: the real-time clock, word 103 of the register page from revision 9
;; (muir's docs/quux.md, "The real-time clock"): unix seconds, unsigned 32
;; bits, read-only, the host's time.  feature word 15 <0> says it is there,
;; and the word reads 0 below revision 9.  it lets a boot know the time
;; without asking the network.  the time zone stays the site's, applied when
;; a time is decoded, so the clock needs only the epoch constant.
(defconst unix-epoch-universal-time 2208988800.
  "The universal time of 1970-01-01 00:00 GMT, where the RTC's count starts.")

(defvar *read-rtc* t
  "NIL keeps INITIALIZE-TIMEBASE from reading the RTC, as SET-LOCAL-TIME does.")

(defun rtc-universal-time ()
  "QUUX's real-time clock as a universal time, or NIL if the machine has none."
  (unless (zerop (si:feature-page-field #o15 #o0001))
    (let ((seconds (%xbus-read (+ si:feature-page-xbus-address #o103))))
      ;; %xbus-read boxes the word as a signed 32-bit number, so from
      ;; 2038-01-19 on the unsigned count comes back negative.
      (when (minusp seconds)
	(incf seconds (expt 2 32.)))
      ;; 0 is an empty register address, not a time.
      (and (plusp seconds)
	   (+ seconds unix-epoch-universal-time)))))

;; quux: with the real-time clock, the wall clock reads it every time (q9,
;; the user's ruling relayed by muir, 2026-09-25): GET-UNIVERSAL-TIME,
;; GET-TIME and all that decode it, the who-line's clock among them.  it is a
;; register read, so it never drifts and needs no resync; the count of
;; seconds on the microsecond clock below follows the machine's time, and
;; on an unpaced engine ran 11 s ahead of the host's clock in 66 s (muir
;; 73c15f0, micro).  without the clock the count stays.  (TIME),
;; timeouts, PROCESS-SLEEP and the scheduler stay on the tick and the
;; microsecond clock, which never jump when the host's clock is set.
(defvar *rtc-offset* nil
  "Seconds the wall clock runs ahead of the RTC, or NIL if it counts without one.
0 unless SET-LOCAL-TIME was given a time; set by INITIALIZE-TIMEBASE.")

(DEFUN INITIALIZE-TIMEBASE (&OPTIONAL UT &aux rtc)
  "Set the clock.
Possible sources of the time include the real-time clock, the network,
and, failing that, the luser who happens to be around."
  ;; the Lambda's battery clock is no longer a source, nor set here.
  ;; quux: its real-time clock is, ahead of the network, which stays the
  ;; source on a machine without one.
  (and (null ut) *read-rtc* (setq ut (setq rtc (rtc-universal-time))))
  (AND (NULL UT) (NOT (SI:GET-SITE-OPTION :STANDALONE)) *NETWORK-TIME-FUNCTION* 
       (SETQ UT (FUNCALL *NETWORK-TIME-FUNCTION*)))
  (TAGBODY
      (AND (NUMBERP UT) (GO DO-IT))
   STRING
      (FORMAT *QUERY-IO* "~&Please type the date and time: ")
      (SETQ UT (READLINE *QUERY-IO*))
      (WHEN (STRING-EQUAL UT "")
	(IF (Y-OR-N-P "Do you want to specify the time or not? ")
	    (GO STRING)
	  (SETQ *LAST-TIME-UPDATE-TIME* NIL)
	  (RETURN-FROM INITIALIZE-TIMEBASE NIL)))
      (CONDITION-CASE (ERROR)
	  (SETQ UT (PARSE-UNIVERSAL-TIME UT 0 NIL T 0))
	(ERROR (SEND ERROR :REPORT *QUERY-IO*)
	       (GO STRING)))
   GIVE-IT-A-SHOT
      (COND ((NOT (Y-OR-N-P (FORMAT NIL "Time is ~A, OK? " (PRINT-UNIVERSAL-DATE UT NIL))))
	     (GO STRING)))
   DO-IT
      ;; quux: the wall clock reads the real-time clock from here on, offset by
      ;; what a time given here differs from it (none if it came from it).
      (or rtc (setq rtc (rtc-universal-time)))
      (WITHOUT-INTERRUPTS
	(IF (NOT (NULL *UT-AT-BOOT-TIME*))
	    ;;if we are randomly changing the time while up, mung uptime
	    (SETQ *UT-AT-BOOT-TIME*
		  (+ *UT-AT-BOOT-TIME* (- UT (GET-UNIVERSAL-TIME))))
	  ;;no real surprise: changing at boot time
	  (SETQ *UT-AT-BOOT-TIME* UT))
	(SETF (VALUES *LAST-TIME-UPDATE-TIME* PREVIOUS-TOP-9-TIME-BITS)
	      (FIXNUM-MICROSECOND-TIME))
	(MULTIPLE-VALUE (*LAST-TIME-SECONDS* *LAST-TIME-MINUTES* *LAST-TIME-HOURS*
			 *LAST-TIME-DAY* *LAST-TIME-MONTH* *LAST-TIME-YEAR*
			 *LAST-TIME-DAY-OF-THE-WEEK* *LAST-TIME-DAYLIGHT-SAVINGS-P*)
	  (DECODE-UNIVERSAL-TIME UT))
	(setq *rtc-offset* (and rtc (- ut rtc)))
	(RETURN-FROM INITIALIZE-TIMEBASE T))))

(DEFUN SET-LOCAL-TIME (&OPTIONAL NEW-TIME)
  (AND (STRINGP NEW-TIME)
       (SETQ NEW-TIME (TIME:PARSE-UNIVERSAL-TIME NEW-TIME)))
  ;; quux: it reads neither the network nor the real-time clock, so with no
  ;; NEW-TIME it still asks for the time.  nothing here writes the clock,
  ;; which is read-only.
  (let ((*network-time-function* nil) (*read-rtc* nil))
    (INITIALIZE-TIMEBASE NEW-TIME)))

;; This is so freshly booted machines don't give out an incorrect time or uptime until
;; they've found out for themselves what the time *really* is.
(ADD-INITIALIZATION "Forget time" '(SETQ TIME:*LAST-TIME-UPDATE-TIME* NIL) '(BEFORE-COLD))
(ADD-INITIALIZATION "Forget uptime" '(SETQ TIME:*UT-AT-BOOT-TIME* NIL) '(BEFORE-COLD))

;;; This must not process-wait, since it can be called inside the scheduler via the who-line
(DEFUN UPDATE-TIMEBASE (&AUX TIME TICK TOP-9-TIME-BITS INCREMENTAL-TOP-10-TIME-BITS
			(OLD-HOUR *LAST-TIME-HOURS*))
  "Update our information on the current time."
  ;; quux: with the real-time clock, decode it instead of counting.
  (when (and *last-time-update-time* *rtc-offset*)
    (return-from update-timebase (update-timebase-from-rtc)))
  (WHEN (NOT (NULL *LAST-TIME-UPDATE-TIME*))
    (WITHOUT-INTERRUPTS
      ;; Put the following code back if the TIME function ever makes any attempt
      ;; to be even close to 60 cycles.  Also change INITIALIZE-TIMEBASE.
      ;(SETQ TIME (TIME)
      ;	 TICK (TRUNC (TIME-DIFFERENCE TIME *LAST-TIME-UPDATE-TIME*) 60.)
      ;	 *LAST-TIME-UPDATE-TIME*
      ;	    (LDB #o0027 (%24-BIT-PLUS (* 60. TICK) *LAST-TIME-UPDATE-TIME*)))
      (SETF (VALUES TIME TOP-9-TIME-BITS)
	    (FIXNUM-MICROSECOND-TIME))
      ;; Don't lose when installing this code,
      ;; if PREVIOUS-TOP-9-TIME-BITS has not been being updated.
      (OR PREVIOUS-TOP-9-TIME-BITS
	  (SETQ PREVIOUS-TOP-9-TIME-BITS TOP-9-TIME-BITS))
      ;; See if we have "missed any ticks" in the low 23. bits;
      ;; Normally we are supposed to be called frequently enough
      ;; that bit 23. never increments twice between calls to this function
      ;; but a long WITHOUT-INTERRUPTS can make that happen.
      (SETQ INCREMENTAL-TOP-10-TIME-BITS
	    (LSH (- TOP-9-TIME-BITS PREVIOUS-TOP-9-TIME-BITS) 1)
	    PREVIOUS-TOP-9-TIME-BITS TOP-9-TIME-BITS)
      ;; In the ordinary course of events, we DO notice bit 23 increment
      ;; because we see the low 23 bits wrap around.
      ;; So don't count those noticed increments in the "extras".
      (IF (< TIME *LAST-TIME-UPDATE-TIME*)
	  (DECF INCREMENTAL-TOP-10-TIME-BITS 2))
      ;; INCREMENTAL-TOP-10-TIME-BITS is now set to twice the number of times
      ;; that bit 23 has incremented since we last ran, that we didn't notice.
      ;; Now feed that many increments into bit 22, one by one.
      ;; When finished with them (if there are any),
      ;; handle the change in the low 23 bits themselves.
      (DO (EXIT-THIS-TIME) (())
	(IF ( INCREMENTAL-TOP-10-TIME-BITS 0)
	    (SETQ TICK (FLOOR (TIME-DIFFERENCE TIME *LAST-TIME-UPDATE-TIME*) 1000000.)
		  EXIT-THIS-TIME T)
	  (SETQ TICK (FLOOR (DPB 1 #o2601 0) 1000000.)))
	(SETQ *LAST-TIME-UPDATE-TIME*
	      (LDB #o0027 (%MAKE-POINTER-OFFSET
			    DTP-FIX
			    (* 1000000. TICK) *LAST-TIME-UPDATE-TIME*)))
	(OR (ZEROP TICK)
	    (< (SETQ *LAST-TIME-SECONDS* (+ *LAST-TIME-SECONDS* TICK)) 60.)
	    (< (PROG1 (SETQ *LAST-TIME-MINUTES* (+ *LAST-TIME-MINUTES*
						   (FLOOR *LAST-TIME-SECONDS* 60.)))
		      (SETQ *LAST-TIME-SECONDS* (\ *LAST-TIME-SECONDS* 60.)))
	       60.)
	    (< (PROG1 (SETQ *LAST-TIME-HOURS* (+ *LAST-TIME-HOURS*
						 (FLOOR *LAST-TIME-MINUTES* 60.)))
		      (SETQ *LAST-TIME-MINUTES* (\ *LAST-TIME-MINUTES* 60.)))
	       24.)
	    ( (PROG1 (SETQ *LAST-TIME-DAY* (1+ *LAST-TIME-DAY*))
		      (SETQ *LAST-TIME-DAY-OF-THE-WEEK*
			    (\ (1+ *LAST-TIME-DAY-OF-THE-WEEK*) 7))
		      (SETQ *LAST-TIME-HOURS* 0))
	       (MONTH-LENGTH *LAST-TIME-MONTH* *LAST-TIME-YEAR*))
	    ( (SETQ *LAST-TIME-DAY* 1
		     *LAST-TIME-MONTH* (1+ *LAST-TIME-MONTH*))
	       12.)
	    (SETQ *LAST-TIME-MONTH* 1
		  *LAST-TIME-YEAR* (1+ *LAST-TIME-YEAR*)))
	(IF EXIT-THIS-TIME
	    (RETURN NIL)
	  (DECF INCREMENTAL-TOP-10-TIME-BITS)))
      (WHEN ( OLD-HOUR *LAST-TIME-HOURS*)
	;; If hour has incremented, turn decoded time into a UT
	;; using the timezone we were using up to now,
	;; use that to decide if we have turned DST on or off,
	;; and then re-decode the time.
	(MULTIPLE-VALUE (*LAST-TIME-SECONDS* *LAST-TIME-MINUTES* *LAST-TIME-HOURS*
			 *LAST-TIME-DAY* *LAST-TIME-MONTH* *LAST-TIME-YEAR*
			 *LAST-TIME-DAY-OF-THE-WEEK* *LAST-TIME-DAYLIGHT-SAVINGS-P*)
	  (DECODE-UNIVERSAL-TIME
	    (ENCODE-UNIVERSAL-TIME
	      *LAST-TIME-SECONDS* *LAST-TIME-MINUTES* *LAST-TIME-HOURS*
	      *LAST-TIME-DAY* *LAST-TIME-MONTH* *LAST-TIME-YEAR*
	      (IF *LAST-TIME-DAYLIGHT-SAVINGS-P*
		  (1- *TIMEZONE*) *TIMEZONE*))))
	;; Update things for GET-INTERNAL-RUN-TIME at least once an hour.
	(GET-INTERNAL-RUN-TIME))
      T)))

;; quux: UPDATE-TIMEBASE on the real-time clock.  like the count, it must not
;; process-wait (the who-line calls it in the scheduler) and returns T.
(defun update-timebase-from-rtc (&aux (old-hour *last-time-hours*))
  (without-interrupts
    (multiple-value (*last-time-seconds* *last-time-minutes* *last-time-hours*
		     *last-time-day* *last-time-month* *last-time-year*
		     *last-time-day-of-the-week* *last-time-daylight-savings-p*)
      (decode-universal-time (+ (rtc-universal-time) *rtc-offset*))))
  ;; as the count does, let GET-INTERNAL-RUN-TIME see (TIME) at least hourly.
  (or (eql old-hour *last-time-hours*)
      (get-internal-run-time))
  t)

(DEFVAR *MONTH-LENGTHS* '#10r(0 31 28 31 30 31 30 31 31 30 31 30 31)
  "One-based list of lengths of months.")

(DEFUN MONTH-LENGTH (MONTH YEAR)
  "Return the number of days in month MONTH in year YEAR.
Knows about leap years.  January is month 1."
  (IF (= MONTH 2)
      (IF (LEAP-YEAR-P YEAR) 29. 28.)
    (NTH MONTH *MONTH-LENGTHS*)))

(DEFUN LEAP-YEAR-P (YEAR)			;2000 is a leap year.  2100 is not.
  "T if YEAR is a leap year."
  (IF (< YEAR 100.)
      (SETQ YEAR (+ 1900. YEAR)))
  (AND (ZEROP (\ YEAR 4))
       (OR (NOT (ZEROP (\ YEAR 100.)))
	   (ZEROP (\ YEAR 400.)))))

(DEFUN DAYLIGHT-SAVINGS-P ()
  "T if we are now in daylight savings time."
  (UPDATE-TIMEBASE)
  *LAST-TIME-DAYLIGHT-SAVINGS-P*)

(DEFUN DEFAULT-YEAR ()
  "Return the current year, minus 1900."
  (UPDATE-TIMEBASE)
  *LAST-TIME-YEAR*)

;;; These are the functions the user should call
;;; If they can't find out what time it is, they return NIL
(DEFF GET-DECODED-TIME 'GET-TIME)
(DEFUN GET-TIME ()
  "Return the current time, decoded into second, hour, day, etc.
Returns NIL if the time is not known (during startup or DISK-SAVE)."
  (DECLARE (VALUES SECONDS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK
		   DAYLIGHT-SAVINGS-P TIMEZONE))
  (AND (UPDATE-TIMEBASE)
       (VALUES *LAST-TIME-SECONDS* *LAST-TIME-MINUTES* *LAST-TIME-HOURS*
	       *LAST-TIME-DAY* *LAST-TIME-MONTH*
	       *LAST-TIME-YEAR*
	       *LAST-TIME-DAY-OF-THE-WEEK* *LAST-TIME-DAYLIGHT-SAVINGS-P*
	       *TIMEZONE*)))

(DEFUN GET-UNIVERSAL-TIME ()
  "Return the current time as a universal-time.
A universal-time is the number of seconds since 01-Jan-1900 00:00-GMT (a bignum)"
  ;; quux: with the real-time clock, it and the offset, with no decoding.
  (if (and *last-time-update-time* *rtc-offset*)
      (+ (rtc-universal-time) *rtc-offset*)
    (UPDATE-TIMEBASE)
    (ENCODE-UNIVERSAL-TIME *LAST-TIME-SECONDS* *LAST-TIME-MINUTES* *LAST-TIME-HOURS*
			   *LAST-TIME-DAY* *LAST-TIME-MONTH* *LAST-TIME-YEAR*
			   (IF *LAST-TIME-DAYLIGHT-SAVINGS-P*
			       (1- *TIMEZONE*) *TIMEZONE*))))


;;;args to format: DAY MONTH MONTH-STRING DONT-PRINT-YEAR-P YEAR2 YEAR4
;;;		   0   1     2            3                 4	  5
(DEFPROP :DD//MM//YY "~D//~2,'0D~*~:[//~2,'0D~]" DATE-FORMAT)		;27/10{/66}
(DEFPROP :DD//MM//YYYY "~D//~2,'0D~*~:[//~*~D~]" DATE-FORMAT)		;27/10{/1966}
(DEFPROP :MM//DD//YY "~*~D//~0@*~2,'0D~2*~:[//~2,'0D~]" DATE-FORMAT)	;10/27{/66}
(DEFPROP :MM//DD//YYYY "~*~D//~0@*~2,'0D~2*~:[//~*~D~]" DATE-FORMAT)	;10/27{/1966}
(DEFPROP :DD-MM-YY "~D-~2,'0D~*~:[-~2,'0D~]" DATE-FORMAT)		;27-10{-66}
(DEFPROP :DD-MM-YYYY "~D-~2,'0D~*~:[-~*~D~]" DATE-FORMAT)		;27-10{-1966}
(DEFPROP :DD-MMM-YY "~D-~*~A~:[-~2,'0D~]" DATE-FORMAT)			;27-Oct{-66}
(DEFPROP :DD-MMM-YYYY "~D-~*~A~:[-~*~D~]" DATE-FORMAT)			;27-Oct{-1966}
(DEFPROP :DD/ MMM/ YY "~D ~*~A~:[ ~2,'0D~]" DATE-FORMAT)		;27 Oct{ 66}
(DEFPROP :DD/ MMM/ YYYY "~D ~*~A~:[ ~*~D~]" DATE-FORMAT)		;27 Oct{ 1966}
(DEFPROP :DDMMMYY "~D~*~A~:[~2,'0D~]" DATE-FORMAT)			;27Oct{66}
(DEFPROP :DDMMMYYYY "~D~*~A~:[~*~D~]" DATE-FORMAT)			;27Oct{1966}
(DEFPROP :YYMMDD "~4*~2,'0D~1@*~2,'0D~0@*~2,'0D" DATE-FORMAT)		;661027
(DEFPROP :YYYYMMDD "~5*~2,'0D~1@*~2,'0D~0@*~2,'0D" DATE-FORMAT)		;19661027
(DEFPROP :YYMMMDD "~3*~:[~2,'0D~]~2@*~A~0@*~2,'0D" DATE-FORMAT)		;{66}Oct27
(DEFPROP :YYYYMMMDD "~3*~:[~*~D~]~2@*~A~0@*~2,'0D" DATE-FORMAT)		;{1966}Oct27
(DEFPROP :YY-MMM-DD "~3*~:[~2,'0D-~]~2@*~A-~0@*~2,'0D" DATE-FORMAT)	;{66-}Oct-27
(DEFPROP :YYYY-MMM-DD "~3*~:[~*~D-~]~2@*~A-~0@*~2,'0D" DATE-FORMAT)	;{1966-}Oct-27
(DEFPROP :YY-MM-DD "~3*~:[~2,'0D-~]~1@*~A-~0@*~2,'0D" DATE-FORMAT)	;{66-}10-27
(DEFPROP :YYYY-MM-DD "~3*~:[~*~D-~]~1@*~A-~0@*~2,'0D" DATE-FORMAT)	;{1966-}10-27

(DEFUN PRINT-CURRENT-TIME (&OPTIONAL (STREAM *STANDARD-OUTPUT*)
				     (DATE-PRINT-MODE *DEFAULT-DATE-PRINT-MODE*))
  "Print the current time on STREAM."
  (AND (UPDATE-TIMEBASE)
       (MULTIPLE-VALUE-BIND (SECONDS MINUTES HOURS DAY MONTH YEAR)
	   (GET-TIME)
         (PRINT-TIME SECONDS MINUTES HOURS DAY MONTH YEAR STREAM DATE-PRINT-MODE))))

(DEFUN PRINT-UNIVERSAL-TIME (UT &OPTIONAL (STREAM *STANDARD-OUTPUT*)
					  TIMEZONE
					  (DATE-PRINT-MODE *DEFAULT-DATE-PRINT-MODE*))
  "Print the universal-time UT on STREAM, interpreting for time zone TIMEZONE.
TIMEZONE is the number of hours earlier than GMT."
  ;;Let DECODE-UNIVERSAL-TIME default the timezone if wanted, as that fcn
  ;;must know to suppress DST iff TIMEZONE is supplied.
  (MULTIPLE-VALUE-BIND (SECONDS MINUTES HOURS DAY MONTH YEAR)
      (DECODE-UNIVERSAL-TIME UT TIMEZONE)
    (PRINT-TIME SECONDS MINUTES HOURS DAY MONTH YEAR STREAM DATE-PRINT-MODE)))

(DEFUN PRINT-TIME (SECONDS MINUTES HOURS DAY MONTH YEAR
		   &OPTIONAL (STREAM *STANDARD-OUTPUT*)
			     (DATE-PRINT-MODE *DEFAULT-DATE-PRINT-MODE*)) 
  "Print time specified on STREAM using date format DATE-PRINT-MODE.
If STREAM is NIL, construct and return a string."
  (WITH-STACK-LIST (DATE-MODE-ARGS DAY MONTH (MONTH-STRING MONTH :SHORT)
				   NIL (YYYY-YY YEAR (NTH-VALUE 5 (GET-DECODED-TIME))) YEAR)
    (FORMAT STREAM "~? ~2,'0D:~2,'0D:~2,'0D"
	    (OR (GET DATE-PRINT-MODE 'DATE-FORMAT)
		(FERROR NIL "Bad type of DATE-PRINT-MODE: ~S" DATE-PRINT-MODE))
	    DATE-MODE-ARGS
	    HOURS MINUTES SECONDS)))

(DEFUN PRINT-CURRENT-DATE (&OPTIONAL (STREAM *STANDARD-OUTPUT*))
  "Print the current date in a verbose form on STREAM.
If STREAM is NIL, construct and return a string."
  (AND (UPDATE-TIMEBASE)
       (MULTIPLE-VALUE-BIND (SECONDS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK)
	   (GET-TIME)
         (PRINT-DATE SECONDS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK STREAM))))

(DEFUN PRINT-UNIVERSAL-DATE (UT &OPTIONAL (STREAM *STANDARD-OUTPUT*) TIMEZONE)
  "Print the universal-time UT in verbose form on STREAM, decoding for TIMEZONE.
If STREAM is NIL, construct and return a string."
  (MULTIPLE-VALUE-BIND (SECONDS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK)
      (DECODE-UNIVERSAL-TIME UT TIMEZONE)
    (PRINT-DATE SECONDS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK STREAM)))

(DEFUN PRINT-DATE (SECONDS MINUTES HOURS DAY MONTH YEAR DAY-OF-THE-WEEK
		   &OPTIONAL (STREAM *STANDARD-OUTPUT*))
  "Print the date and time in verbose form on STREAM.
If STREAM is NIL, construct and return a string."
  (SETQ MONTH (MONTH-STRING MONTH)
	DAY-OF-THE-WEEK (DAY-OF-THE-WEEK-STRING DAY-OF-THE-WEEK))
  (FORMAT STREAM
	  "~A the ~:R of ~A, ~D; ~D:~2,'0D:~2,'0D ~A"
	  DAY-OF-THE-WEEK DAY MONTH YEAR (1+ (\ (+ HOURS 11.) 12.)) MINUTES SECONDS
	  (COND ((AND (ZEROP SECONDS)
		      (ZEROP MINUTES)
		      (MEMQ HOURS '(0 12.)))
		 (IF (= HOURS 0) "midnight" "noon"))
		(( HOURS 12.) "pm")
		(T "am"))))

(DEFUN PRINT-BRIEF-UNIVERSAL-TIME (UT &OPTIONAL (STREAM *STANDARD-OUTPUT*)
						(REF-UT (GET-UNIVERSAL-TIME))
						(DATE-PRINT-MODE *DEFAULT-DATE-PRINT-MODE*))
  "Prints only those aspects of the time, UT, that differ from the current time.
Also never prints seconds.  Used by notifications, for example.
If STREAM is NIL, construct and return a string."
  (MULTIPLE-VALUE-BIND (IGNORE MINUTES HOURS DAY MONTH YEAR)
      (DECODE-UNIVERSAL-TIME UT)
    (MULTIPLE-VALUE-BIND (IGNORE IGNORE IGNORE REF-DAY REF-MONTH REF-YEAR)
	(DECODE-UNIVERSAL-TIME REF-UT)
      ;; If not same day, print month and day numerically
      (IF (OR ( DAY REF-DAY) ( MONTH REF-MONTH) ( YEAR REF-YEAR))
	  (WITH-STACK-LIST (DATE-MODE-ARGS DAY MONTH (MONTH-STRING MONTH :SHORT)
					   (= YEAR REF-YEAR) (YYYY-YY YEAR REF-YEAR) YEAR)
	    (FORMAT STREAM "~? ~2,'0D:~2,'0D"
		    (OR (GET DATE-PRINT-MODE 'DATE-FORMAT)
			(FERROR NIL "Bad type-of DATE-PRINT-MODE: ~S" DATE-PRINT-MODE))
		    DATE-MODE-ARGS
		    HOURS MINUTES))
	;; Always print hours colon minutes, even if same as now
	(FORMAT STREAM "~2,'0D:~2,'0D" HOURS MINUTES)))))

(DEFUN PRINT-UPTIME (&OPTIONAL (STREAM *STANDARD-OUTPUT*))
  "Print how long this machine has been up since last cold boot."
  (FORMAT STREAM "~&This machine has been up ~\time-interval\."
	  (- (TIME:GET-UNIVERSAL-TIME) TIME:*UT-AT-BOOT-TIME*)))



;;;; Some useful strings and accessing functions.

;;; Days of the week.  Elements must be (in order):
;;; (1) Three-letter form.
;;; (2) Full spelling.
;;; (3) Middle-length form if any, else NIL.
;;; (4) Francais.
;;; (5) Deutsch.
;;; (6) Italian.  ; How do you say that in Italian ?

(DEFVAR *DAYS-OF-THE-WEEK* '(("Mon" "Monday" NIL "Lundi" "Montag" "Lunedi")
			     ("Tue" "Tuesday" "Tues" "Mardi" "Dienstag" "Martedi")
			     ("Wed" "Wednesday" NIL "Mercredi" "Mittwoch" "Mercoledi")
			     ("Thu" "Thursday" "Thurs" "Jeudi" "Donnerstag" "Giovedi")
			     ("Fri" "Friday" NIL "Vendredi" "Freitag" "Venerdi")
			     ("Sat" "Saturday" NIL "Samedi" "Samstag" "Sabato")
			     ("Sun" "Sunday" NIL "Dimanche" "Sonntag" "Domenica"))
	"The list of the days of the week in short, long, medium, French, German, Italian." )

(DEFUN DAY-OF-THE-WEEK-STRING (DAY-OF-THE-WEEK &OPTIONAL (MODE :LONG) &AUX STRINGS)
  (SETQ STRINGS (NTH DAY-OF-THE-WEEK *DAYS-OF-THE-WEEK*))
  (CASE MODE
    (:SHORT (FIRST STRINGS))
    (:LONG (SECOND STRINGS))
    (:MEDIUM (OR (THIRD STRINGS) (FIRST STRINGS)))
    (:FRENCH (FOURTH STRINGS))
    (:GERMAN (FIFTH STRINGS))
    (:ITALIAN (SIXTH STRINGS))			; After this, perhaps NDOWSS ?
    (OTHERWISE (FERROR NIL "~S is not a known day-of-the-week mode" MODE))))


;;; Months of the year:  Elements must be (in order):
;;; (1) Three-letter form.
;;; (2) Full spelling.
;;; (3) Middle-length form if any, else NIL.
;;; (4) Francais.
;;; (5) Roman numerals (used in Europe).
;;; (6) Deutsch.
;;; (7) Italian.

(DEFVAR *MONTHS* '(("Jan" "January" NIL "Janvier" "I" "Januar" "Genniao")
		   ("Feb" "February" NIL "Fevrier" "II" "Februar" "Febbraio")
		   ("Mar" "March" NIL "Mars" "III" "Maerz" "Marzo")
		   ("Apr" "April" NIL "Avril" "IV" "April" "Aprile")
		   ("May" "May" NIL "Mai" "V" "Mai" "Maggio")
		   ("Jun" "June" NIL "Juin" "VI" "Juni" "Giugno")
		   ("Jul" "July" NIL "Juillet" "VII" "Juli" "Luglio")
		   ("Aug" "August" NIL "Aout" "VIII" "August" "Agosto")
		   ("Sep" "September" "Sept" "Septembre" "IX" "September" "Settembre")
		   ("Oct" "October" NIL "Octobre" "X" "Oktober" "Ottobre")
		   ("Nov" "November" "Novem" "Novembre" "XI" "November" "Novembre")
		   ("Dec" "December" "Decem" "Decembre" "XII" "Dezember" "Dicembre"))
  "List of names lists of names of months: short, long, medium, French, Roman, German, Italian")

(DEFUN MONTH-STRING (MONTH &OPTIONAL (MODE :LONG) &AUX STRINGS)
  (SETQ STRINGS (NTH (1- MONTH) *MONTHS*))
  (CASE MODE
    (:SHORT (FIRST STRINGS))
    (:LONG (SECOND STRINGS))
    (:MEDIUM (OR (THIRD STRINGS) (FIRST STRINGS)))
    (:FRENCH (FOURTH STRINGS))
    (:ROMAN (FIFTH STRINGS))
    (:GERMAN (SIXTH STRINGS))
    (:ITALIAN (SEVENTH STRINGS))
    (OTHERWISE (FERROR NIL "~S is not a known month mode" MODE))))

(DEFVAR *TIMEZONES* '((0 "GMT" NIL #/Z)			;Greenwich
		      (0 "UT" NIL #/Z)
		      (1 NIL NIL #/A)
		      (2 NIL NIL #/B)
		      (3 NIL "ADT" #/C)
		      (4 "AST" "EDT" #/D)		;Atlantic
		      (5 "EST" "CDT" #/E)		;Eastern
		      (6 "CST" "MDT" #/F)		;Central
		      (7 "MST" "PDT" #/G)		;Mountain
		      (8 "PST" "YDT" #/H)		;Pacific
		      (9 "YST" "HDT" #/I)		;Yukon
		      (10. "HST" "BDT" #/K)		;Hawaiian
		      (11. "BST" NIL #/L)		;Bering
		      (12. NIL NIL #/M)
		      (-1 NIL NIL #/N)
		      (-2 NIL NIL #/O)
		      (-3 NIL NIL #/P)
		      (-4 NIL NIL #/Q)
		      (-5 NIL NIL #/R)
		      (-6 NIL NIL #/S)
		      (-7 NIL NIL #/T)
		      (-8 NIL NIL #/U)
		      (-9 NIL NIL #/V)
		      (-10. NIL NIL #/W)
		      (-11. NIL NIL #/X)
		      (-12. NIL NIL #/Y)
		      (3.5 "NST" NIL -1)		;Newfoundland
		      )
  "List of timezones: offset from gmt, name, daylight-savings-name, military character.")

(DEFUN TIMEZONE-STRING (&OPTIONAL (TIMEZONE *TIMEZONE*)
				  (DAYLIGHT-SAVINGS-P (DAYLIGHT-SAVINGS-P)))
  "Return a string describing timezone TIMEZONE, optionally for daylight savings time.
Defaults are our own timezone, and DST if it is now in effect."
  (IF DAYLIGHT-SAVINGS-P
      (THIRD (ASSQ (1- TIMEZONE) *TIMEZONES*))
      (SECOND (ASSQ TIMEZONE *TIMEZONES*))))

;;;; Date and time parsing

(DEFMACRO BAD-DATE-OR-TIME (REASON . ARGS)
  `(*THROW 'BAD-DATE-OR-TIME ,(IF (NULL ARGS) REASON `(FORMAT NIL ,REASON . ,ARGS))))

(DEFUN VERIFY-DATE (DAY MONTH YEAR DAY-OF-THE-WEEK)
  "If the day of the week of the date specified by DATE, MONTH, and YEAR
is the same as DAY-OF-THE-WEEK, return NIL; otherwise, return a string that
contains a suitable error message. If YEAR is less than 100, it is shifted
by centuries until it is within 50 years of the present."
  (COND ((> DAY (MONTH-LENGTH MONTH YEAR))
	 (FORMAT NIL "~A only has ~D day~:P" (MONTH-STRING MONTH) (MONTH-LENGTH MONTH YEAR)))
	(DAY-OF-THE-WEEK
	 (LET ((UT (ENCODE-UNIVERSAL-TIME 0 0 0 DAY MONTH YEAR)))
	   (MULTIPLE-VALUE-BIND (NIL NIL NIL NIL NIL NIL CORRECT-DAY-OF-THE-WEEK)
	       (DECODE-UNIVERSAL-TIME UT)
	     (AND ( DAY-OF-THE-WEEK CORRECT-DAY-OF-THE-WEEK)
		  (FORMAT NIL "The ~:R of ~A, ~D is a ~A, not a ~A"
			  (MONTH-STRING MONTH) DAY YEAR
			  (DAY-OF-THE-WEEK-STRING CORRECT-DAY-OF-THE-WEEK)
			  (DAY-OF-THE-WEEK-STRING DAY-OF-THE-WEEK))))))
	(T
	 NIL)))

(ADD-INITIALIZATION "Initialize Timebase" 
  '(PROGN (SETQ LAST-BOOT-TIME (TIME) WAS-NEGATIVE NIL HIGH-TIME-BITS 0)
	  (INITIALIZE-TIMEBASE))
  '(:WARM :NOW))
