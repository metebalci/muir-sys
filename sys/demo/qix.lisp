;;; -*- Mode:LISP;  Base:8.;  Package:HACKS;  Lowercase: T -*-

(defun qix (&optional (length 100) (stream terminal-io) (times NIL))
 (with-real-time
   (let* ((list (make-list (1+ length)))
	  (history (nthcdr (1- length) list)))
     (%p-store-cdr-code (cdr history) cdr-error)
     (%p-store-cdr-code history cdr-normal)
     (rplacd history list)
     (send stream ':clear-screen)
     (loop repeat length
	   for h = history then (cdr h)
	   do (setf (car h) (make-list 4)))
     (multiple-value-bind (xlim ylim)
	 (send stream ':inside-size)
       (loop with x1 = 0
	     and y1 = (1- ylim)
	     and x2 = 0
	     and y2 = (1- ylim)
	     and dx1 = 5
	     and dy1 = 12
	     and dx2 = 12
	     and dy2 = 5
	     with tem
	     until (or (send stream ':tyi-no-hang)
		       (if times (= (setq times (1- times)) 0) NIL))
	     when (caar history)
	     do (send stream ':draw-line
		      (first (car history))
		      (second (car history))
		      (third (car history))
		      (fourth (car history))
		      tv:alu-xor)
	     do (setf (first (car history)) x1)
	     (setf (second (car history)) y1)
	     (setf (third (car history)) x2)
	     (setf (fourth (car history)) y2)
	     (setq history (cdr history))
	     (send stream ':draw-line x1 y1 x2 y2 tv:alu-xor)
	     (setq dx1 (1- (+ dx1 (random 3)))
		   dy1 (1- (+ dy1 (random 3)))
		   dx2 (1- (+ dx2 (random 3)))
		   dy2 (1- (+ dy2 (random 3))))
	     (cond ((> dx1 12) (setq dx1 12))
		   ((< dx1 -12) (setq dx1 -12)))
	     (cond ((> dy1 12) (setq dy1 12))
		   ((< dy1 -12) (setq dy1 -12)))
	     (cond ((> dx2 12) (setq dx2 12))
		   ((< dx2 -12) (setq dx2 -12)))
	     (cond ((> dy2 12) (setq dy2 12))
		   ((< dy2 -12) (setq dy2 -12)))
	     (cond ((or ( (setq tem (+ x1 dx1)) xlim)
			(minusp tem))
		    (setq dx1 (- dx1))))
	     (cond ((or ( (setq tem (+ x2 dx2)) xlim)
			(minusp tem))
		    (setq dx2 (- dx2))))
	     (cond ((or ( (setq tem (+ y1 dy1)) ylim)
			(minusp tem))
		    (setq dy1 (- dy1))))
	     (cond ((or ( (setq tem (+ y2 dy2)) ylim)
			(minusp tem))
		    (setq dy2 (- dy2))))
	     (setq x1 (+ x1 dx1)
		     y1 (+ y1 dy1)
		     x2 (+ x2 dx2)
		     y2 (+ y2 dy2))
	  finally (loop repeat length
			when (caar history)
			 do (send stream ':draw-line
				  (first (car history))
				  (second (car history))
				  (third (car history))
				  (fourth (car history))
				  tv:alu-xor)
			do (setq history (cdr history))))))))

(defdemo "Qix" "Not the arcade game" (qix))