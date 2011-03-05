(eval-when (:compile-toplevel :load-toplevel :execute) 
  (require :asdf)
  (require :v4l2)
  (require :sb-posix))

(defpackage :run
  (:use :cl :v4l2))

(in-package :run)

(defmacro parse-capabilities (cap)
  (let* ((caps '(video-capture video-output video-overlay vbi-capture
		 vbi-output sliced-vbi-capture sliced-vbi-output rds-capture
		 video-output-overlay hw-freq-seek rds-output tuner audio
		 radio modulator readwrite asyncio streaming))
	 (vcaps (loop for e in caps collect
		     (intern (symbol-name e) 'v4l2))))
    `(list ,@(loop for e in vcaps 
	   collect
		  `(list ',e (= ,e (logand ,cap ,e)))))))

(defvar *fd* nil)
#+nil
(defvar *fd* (sb-posix:open "/dev/video0" sb-posix:o-rdwr))

(defun supports-streaming-p (fd)
  (let ((cap (v4l2::allocate-capability)))
    (sb-posix:ioctl fd v4l2::io-query-capability cap)
    (prog1 (= v4l2::streaming 
	      (logand (v4l2::capability-capabilities cap)
		      v4l2::streaming))
      (v4l2::free-capability cap))))

#+nil
(supports-streaming-p *fd*)

#+nil
(sb-posix:close *fd*)

(defun supports-mmap-p (fd)
 (let ((rb (v4l2::allocate-request-buffers)))
   (setf (v4l2::request-buffers-type rb) 'v4l2::video-capture
	 (v4l2::request-buffers-memory rb) 'v4l2::memory-mmap)
   (prog1
       (/= -1 (sb-posix:ioctl fd v4l2::io-reqbufs rb))
     (v4l2::free-request-buffers rb))))

(defun supports-user-pointer-p (fd)
 (let ((rb (v4l2::allocate-request-buffers)))
   (setf (v4l2::request-buffers-type rb) 'v4l2::video-capture
	 (v4l2::request-buffers-memory rb) 'v4l2::memory-user-pointer)
   (prog1
       (/= -1 (sb-posix:ioctl fd v4l2::io-reqbufs rb))
     (v4l2::free-request-buffers rb))))

#+nil
(supports-user-pointer-p *fd*)
#+nil
(supports-mmap-p *fd*)

(defun init-mmap (fd &optional (count 30))
  "Allocate buffers for image storage with MMAP."
  (let ((res ())
	(rb (v4l2::allocate-request-buffers)))
    (setf (v4l2::request-buffers-type rb) 'v4l2::video-capture
	  (v4l2::request-buffers-memory rb) 'v4l2::memory-mmap
	  (v4l2::request-buffers-count rb) count)
    (when (= -1 (sb-posix:ioctl fd v4l2::io-reqbufs rb))
      (error "video capture or mmap streaming not supported."))
    (assert (<= count (v4l2::request-buffers-count rb)))
    (dotimes (i (v4l2::request-buffers-count rb))
      (let ((b (v4l2::allocate-buffer)))
	(setf (v4l2::buffer-type b) 'v4l2::video-capture
	      (v4l2::buffer-memory b) 'v4l2::memory-mmap
	      (v4l2::buffer-index b) i)
	(assert (/= -1 (sb-posix:ioctl fd v4l2::io-querybuf b)))
	(let ((len (v4l2::buffer-length b)))
	  (push (list (sb-posix:mmap (sb-sys:int-sap 0)
				     len
				     (logior sb-posix:prot-read
					     sb-posix:prot-write)
				     sb-posix:map-shared
				     fd
				     (v4l2::buffer-offset b))
		      len
		      i
		      nil)
		res))
	(v4l2::free-buffer b)))
    (v4l2::free-request-buffers rb)
    (reverse res)))

(defun uninit-mmap (bufs)
  (loop for (start len index is-queued) in bufs do
       (sb-posix:munmap start len)))

(defun set-format (fd)
  (let* ((f (v4l2::allocate-format))
	 (p (sb-alien:slot f 'v4l2::pix)))
    (setf (v4l2::format-type f) 'v4l2::video-capture
	  (sb-alien:slot p 'v4l2::width) 640
	  (sb-alien:slot p 'v4l2::height) 480
	  (sb-alien:slot p 'v4l2::pixelformat) v4l2::yuyv)
    (sb-posix:ioctl fd v4l2::io-set-format f)
    (v4l2::free-format f)))
#+nil
(set-format *fd*)

(defvar *bufs* nil)
#+nil
(setf *bufs* (init-mmap *fd*))

#+nil
(uninit-mmap *bufs*)

(defun enqueue (fd buf)
  (destructuring-bind (start len index is-queued) buf
    (declare (ignore start len))
    (unless is-queued
     (let ((b (v4l2::allocate-buffer)))
       (setf (v4l2::buffer-type b) 'v4l2::video-capture
	     (v4l2::buffer-memory b) 'v4l2::memory-mmap
	     (v4l2::buffer-index b) index)
       (when (= -1 (sb-posix:ioctl fd v4l2::io-qbuf b))
	 (break "qbuf error maybe buffer has been queued already?"))
       (setf (fourth buf) t)
       (v4l2::free-buffer b)))))

(defun exchange-queue (fd process-img)
  (unless fd
    (error "file descriptor isn't opened."))
  (unless *bufs*
    (error "no mmap buffers available."))
  (let ((b (v4l2::allocate-buffer)))
    (setf (v4l2::buffer-type b) 'v4l2::video-capture
	  (v4l2::buffer-memory b) 'v4l2::memory-mmap)
    (sb-posix:ioctl fd v4l2::io-dqbuf b)
    (funcall process-img (v4l2::buffer-index b))
    (sb-posix:ioctl fd v4l2::io-qbuf b)
    (v4l2::free-buffer b)))

(defun init ()
  (setf *fd* (sb-posix:open "/dev/video0" sb-posix:o-rdwr))
  (set-format *fd*)
  (setf *bufs* (init-mmap *fd*)))


(defun uninit ()
  (uninit-mmap *bufs*)
  (setf *bufs* nil)
  (sb-posix:close *fd*)
  (setf *fd* nil))

(defun start-capturing ()
  (unless *bufs*
    (error "You forgot to call init-mmap."))
  (dolist (e *bufs*) 
    (enqueue *fd* e))
  (sb-alien:with-alien ((v sb-alien:integer :local v4l2::video-capture))
    (assert (/= -1 (sb-posix:ioctl *fd* 
				   v4l2::io-streamon
				   (sb-alien:addr v))))))

(defun stop-capturing ()
  (sb-alien:with-alien ((v sb-alien:integer :local v4l2::video-capture))
    (assert (/= -1 (sb-posix:ioctl *fd* 
				   v4l2::io-streamoff
				   (sb-alien:addr v))))))

#+nil
(stop-capturing)

(defun query-controls (fd)
  (let ((c (v4l2::allocate-query-control))
	(res ()))
    (unwind-protect
	 (dolist (e '(brightness  contrast saturation  hue
		      auto-white-balance ;red-balance blue-balance
		      gamma
		      ;exposure 
		      ; autogain ; gain ; hflip vflip
		      power-line-frequency ;hue-auto white-balance-temperature
		      sharpness ;backlight-compensation chroma-agc color-killer
		      ;autobrightness ;band-stop-filter
		      ))
	   (setf (v4l2::query-control-id c) (symbol-value
					     (intern (symbol-name e) 'v4l2)))
	   (sb-posix:ioctl fd v4l2::io-query-control c)
       (unless (= v4l2::flag-disabled 
		  (logand v4l2::flag-disabled (v4l2::query-control-flags c)))
	 (push (list e 
		     (v4l2::query-control-minimum c)
		     (v4l2::query-control-default-value c)
		     (v4l2::query-control-maximum c)) res)))
      (v4l2::free-query-control c))
    (reverse res)))
#+nil
(query-controls *fd*)

(defun start-main-loop ()
  (unwind-protect
       (progn 
	 (init)
	 (start-capturing)
	 (time
	  (dotimes (i 100)
	    (exchange-queue *fd* #'(lambda (index)
				     (format t "~a~%"
					     (sb-sys:sap-ref-8 
					      (first (elt *bufs* index))
					      0)))))))
    (stop-capturing)))

#+nil
(start-main-loop)

#+nil
(uninit)