; -*- Mode:Lisp; Lowercase:True; Base:8 -*-

; Bolio init file for window system documentation

(include ((dsk bolio)justdf #+TENEX lisp))

; Why aren't these declared??
(declare (special defun-pre-leading environment-type request-eol-p))

; Flavor documentation guy punches out forms like
;  (defprop flavor-name string flavor-documentation)

(defprop flavor-documentation flavor-documentation-request request)
(defun flavor-documentation-request ()
  (let ((flavor-name-string (get-word-string)) (flavor-name) (tem))
    (setq flavor-name (string-intern flavor-name-string))
    (flush-request-line)
    (cond ((setq tem (get flavor-name 'flavor-documentation))
	   (jin-push tem)				;I wonder if all this BS works?
	   (jin-push flavor-name-string)
	   (jin-push '|/
/
|)
	   (let ((request-eol-p nil))
	     (defflavor-request))
	   (end-defflavor-request))
	  (t (barf flavor-name '|has no flavor-documentation property|)))))

; Message and flavor and initoption indices

(setq flavor-index nil)
(defprop flavor-index |Flavor Index| index-title)
(defprop flavor-index 2 index-columns)

(setq message-index nil)
(defprop message-index |Message Index| index-title)
(defprop message-index 2 index-columns)

(setq initoption-index nil)
(defprop initoption-index |Window Creation Options| index-title)
(defprop initoption-index 2 index-columns)

;.defflavor, .defmethod, and .defmessage requests

(defprop defmessage defmessage-request request)
(defprop defmessage1 defmessage1-request request)
(defprop end_defmessage end-defmessage-request request)

(defun defmessage-request ()
  (check-env 'text 'defmessage)
  (or (need-space-mills 1000.) ;1 inch
      (output-leading-mills defun-pre-leading))
  (check-font-status text-font)
  ((lambda (left-indent environment-type extra-left-indent-first-line-of-paragraph)
      (defmessage1-request)  ;Gobble the arguments, put out line, index, etc.
      (flush-request-line)
      (defun-horrible-tab-crock)
      (*catch 'defmessage (main-loop)))
   (convert-mills 500.) ;1/2 inch indent
   'defmessage
   0))

(defun defmessage1-request ()
  (check-env 'defmessage 'defmessage1)
  (setq cur-hpos 0)
  ((lambda (message-name jin-cur-font)
      (or message-name (barf '|Message name missing in .defmessage or .defmessage1|))
      (add-to-index message-name 'message-index)
      (auto-setq message-name '|message|)
      (set-hpos left-margin)
      (put-string-flush-left message-name)
      (defun-line-proc))
   (get-word-string)
   lisp-title-font)
  (setq begin-new-paragraph nil))

(defun end-defmessage-request ()
  (check-env 'defmessage 'end_defmessage)
  (check-font-status text-font)
  (*throw 'defmessage nil))

(defprop defmethod defmethod-request request)
(defprop defmethod1 defmethod1-request request)
(defprop end_defmethod end-defmethod-request request)

(defun defmethod-request ()
  (check-env 'text 'defmethod)
  (or (need-space-mills 1000.) ;1 inch
      (output-leading-mills defun-pre-leading))
  (check-font-status text-font)
  ((lambda (left-indent environment-type extra-left-indent-first-line-of-paragraph)
      (defmethod1-request)  ;Gobble the arguments, put out line, index, etc.
      (flush-request-line)
      (defun-horrible-tab-crock)
      (*catch 'defmethod (main-loop)))
   (convert-mills 500.) ;1/2 inch indent
   'defmethod
   0))

(declare (special defmethod-suppress-flavor-name))
(setq defmethod-suppress-flavor-name nil)

(defun defmethod1-request ()
  (check-env 'defmethod 'defmethod1)
  (setq cur-hpos 0)
  ((lambda (flavor-name message-name)
      (or flavor-name (barf '|Flavor name missing in .defmethod or .defmethod1|))
      (or message-name (barf '|Message name missing in .defmethod or .defmethod1|))
      (add-to-index (string-append message-name '|  (to | flavor-name '|)|) 'message-index)
      (just-setq (string-intern (string-append flavor-name '|-|
				       (substring message-name 1 (string-length message-name))
				       '|-method|))
		 (string-append '|page | (string-number page-number)))
      (set-hpos left-margin)
      (let ((jin-cur-font lisp-title-font))
	(put-string-flush-left message-name))
      (defun-line-proc-no-newline)
      (cond ((not defmethod-suppress-flavor-name)
	     (let ((jin-cur-font lisp-text-font))
	       (put-string-flush-left-maybe-terpri-first
		 (string-append '|1(to *| flavor-name '|1)*|)))))
      (defun-line-proc-newline))
   (get-word-string)
   (get-word-string)))

(defun end-defmethod-request ()
  (check-env 'defmethod 'end_defmethod)
  (check-font-status text-font)
  (*throw 'defmethod nil))

(defprop defflavor defflavor-request request)
(defprop end_defflavor end-defflavor-request request)

(defun defflavor-request ()
  (check-env 'text 'defflavor)
  (or (need-space-mills 1000.)	;1 inch
      (output-leading-mills defun-pre-leading))
  (check-font-status text-font)
  (setq cur-hpos 0)
  ((lambda (left-indent environment-type extra-left-indent-first-line-of-paragraph
	    flavor-name jin-cur-font)
      (or flavor-name (barf '|Flavor name missing in .defflavor|))
      (add-to-index flavor-name 'flavor-index)
      (auto-setq flavor-name '|flavor|)
      (set-hpos left-margin)
      (put-string-flush-left flavor-name)
      (jout-white-space (convert-mills 200.))
      (setq jin-cur-font italic-font)
      (cond (request-eol-p (put-string-flush-left (string '|Flavor|)))
	    (t (put-string-flush-left (get-line-string))))
      (setq jin-cur-font text-font)
      (line-advance)
      (setq begin-new-paragraph nil)
      (defun-horrible-tab-crock)
      (*catch 'defflavor (main-loop)))
   (convert-mills 500.) ;1/2 inch indent
   'defflavor
   0
   (get-word-string)
   lisp-title-font))

(defun end-defflavor-request ()
  (check-env 'defflavor 'end_defflavor)
  (check-font-status text-font)
  (*throw 'defflavor nil))

(defprop definitoption definitoption-request request)
(defprop definitoption1 definitoption1-request request)
(defprop end_definitoption end-definitoption-request request)

(defun definitoption-request ()
  (check-env 'text 'definitoption-request)
  (or (need-space-mills 1000.)	;1 inch
      (output-leading-mills defun-pre-leading))
  (check-font-status text-font)
  ((lambda (left-indent environment-type extra-left-indent-first-line-of-paragraph)
      (definitoption1-request)
      (setq begin-new-paragraph nil)
      (defun-horrible-tab-crock)
      (*catch 'definitoption (main-loop)))
   (convert-mills 500.) ;1/2 inch indent
   'definitoption
   0))

(defun definitoption1-request ()
  (let ((flavor-name (get-word-string))
	(option-name (get-word-string))
	(jin-cur-font lisp-title-font))
    (check-env 'definitoption 'definitoption1-request)
    (setq cur-hpos 0)
    (or flavor-name (barf '|Flavor name missing in .definitoption|))
    (or option-name (barf '|Option name missing in .definitoption|))
    (add-to-index (string-append option-name '|  (for | flavor-name '|)|)
		  'initoption-index)
    (just-setq (string-intern (string-append flavor-name '|-|
				 (substring option-name 1 (string-length option-name))
				 '|-init-option|))
	       (string-append '|page | (string-number page-number)))
    (set-hpos left-margin)
    (put-string-flush-left option-name)
    (defun-line-proc-no-newline)
    (let ((jin-cur-font lisp-text-font))
      (put-string-flush-left-maybe-terpri-first
         (string-append '|1(Init Option for *| flavor-name '|1)*|)))
    (defun-line-proc-newline)))

(defun end-definitoption-request ()
  (check-env 'definitoption 'end_definitoption)
  (check-font-status text-font)
  (*throw 'definitoption nil))

(defprop defresource defresource-request request)
(defprop defresource1 defresource1-request request)
(defprop end_defresource end-defresource-request request)

(defun defresource-request ()
  (check-env 'text 'defresource)
  (or (need-space-mills 1000.) ;1 inch
      (output-leading-mills defun-pre-leading))
  (check-font-status text-font)
  ((lambda (left-indent environment-type extra-left-indent-first-line-of-paragraph)
      (defresource1-request)  ;Gobble the arguments, put out line, index, etc.
      (flush-request-line)
      (defun-horrible-tab-crock)
      (*catch 'defresource (main-loop)))
   (convert-mills 500.) ;1/2 inch indent
   'defresource
   0))

(defun defresource1-request ()
  (check-env 'defresource 'defresource1)
  (setq cur-hpos 0)
  ((lambda (resource-name jin-cur-font)
      (or resource-name (barf '|Resource name missing in .defresource or .defresource1|))
      (add-to-index resource-name 'resource-index)
      (auto-setq resource-name '|resource|)
      (set-hpos left-margin)
      (put-string-flush-left resource-name)
      (defun-line-proc-no-newline)
      (put-string-flush-left-maybe-terpri-first '|1(Resource)*|)
      (defun-line-proc-newline))
   (get-word-string)
   lisp-title-font)
  (setq begin-new-paragraph nil))

(defun end-defresource-request ()
  (check-env 'defresource 'end_defresource)
  (check-font-status text-font)
  (*throw 'defresource nil))

;Code copied out of the middle of defun-line-proc
(declare (special DEFUN-ARG-SEPARATION-INTERNAL DEFUN-CONTINUATION-INDENT-INTERNAL))

(defun put-string-flush-left-maybe-terpri-first (string)
  (cond ((> (+ cur-hpos DEFUN-ARG-SEPARATION-INTERNAL (string-push-get-width string))
	    (- right-margin right-indent))
	 (line-advance)
	 (jout-white-space
	   (setq cur-hpos (+ left-margin left-indent
			     DEFUN-CONTINUATION-INDENT-INTERNAL))))
	(t (jout-white-space DEFUN-ARG-SEPARATION-INTERNAL)
	   (setq cur-hpos (+ cur-hpos DEFUN-ARG-SEPARATION-INTERNAL))))
  (output-nofill-line)				; output buffered string
  (jin-cleanup))

; Set up style and fonts

(default-manual-style nil '|New Window System|)

