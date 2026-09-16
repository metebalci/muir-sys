;;; -*- Mode:LISP; Readtable:CL; Base:10 -*- See where a random walk goes in a square playing board


(defvar board (make-array '(20 20) :initial-element 0.0))
(defvar temp  (make-array '(20 20) :initial-element 0.0))

(defun walk ()
  (z board)
  (setf (aref board 10 10) 1.0)
  (send standard-output :clear-screen)
  (loop
    (send standard-output :set-cursorpos 0 0)
    (d board)
    (z temp)
    (do ((i 1 (1+ i)))
	((>= i 19.))
      (do ((j 1 (1+ j)))
	  ((>= j 19.))
	(setf (aref temp i j) (/ (+ (aref board i (1+ j))
				    (aref board i (1- j))
				    (aref board (1+ i) j)
				    (aref board (1- i) j)) 4.0))))
    (s board temp)
    (princ "--more--")
    (tyi)))

(defun d (board)
  "Display"
  (let ((quarter (/ (hi board) 4.0)))
    (dotimes (i 20)
      (send standard-output :fresh-line)
      (dotimes (j 20)
	(send standard-output :tyo (nth (truncate (aref board i j) quarter)
		    '(#\Space #\. #\: #\* #\X)))
	(send standard-output :tyo #\Space)))))

(defun p (board)
  "Print"
  (dotimes (i 20)
    (send standard-output :fresh-line)
    (dotimes (j 20)
      (format t "~S " (aref board i j)))))

(defun hi (board)
  "High"
  (let ((n most-negative-short-float))
    (dotimes (i 20)
      (dotimes (j 20)
	(setf n (max n (aref board i j)))))
    n))

(defun z (board)
  "Zero"
  (dotimes (i 20)
    (dotimes (j 20)
      (setf (aref board i j) 0.0))))

(defun s (sink source)
  "Set"
  (dotimes (i 20)
    (dotimes (j 20)
      (setf (aref sink i j) (aref source i j)))))