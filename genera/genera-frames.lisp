;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Package: GENERA-CLIM; Base: 10; Lowercase: Yes -*-

(in-package :genera-clim)

"Copyright (c) 1992 Symbolics, Inc.  All rights reserved."
;;; $fiHeader$

(defclass genera-frame-manager (standard-frame-manager)
    ())

(defmethod make-frame-manager ((port genera-port))
  (make-instance 'genera-frame-manager :port port))

(defmethod adopt-frame :after ((framem genera-frame-manager)
			       (frame standard-application-frame))
  ;;--- This would establish callbacks...
  )


(defmethod frame-wrapper ((framem genera-frame-manager) 
			  (frame standard-application-frame) pane)
  (let ((menu-bar (slot-value frame 'menu-bar)))
    (if menu-bar
	(with-look-and-feel-realization (framem frame)
	  (vertically ()
	    (realize-pane 'application-pane
			  :display-function 
			    `(display-command-menu :command-table ,menu-bar)
			  :width :compute :height :compute)
	    pane))
	pane)))

(defun display-command-menu (frame stream &rest keys
			     &key command-table &allow-other-keys)
  (declare (dynamic-extent keys))
  (when (or (null command-table)
	    (eql command-table t))
    (setq command-table (frame-command-table frame)))
  (with-keywords-removed (keys keys '(:command-table))
    (apply #'display-command-table-menu command-table stream keys)))

(defmethod port-dialog-view ((port genera-port))
  +textual-dialog-view+)
  
;;--- Should "ungray" the command button, if there is one
(defmethod note-command-enabled ((framem genera-frame-manager) frame command)
  (declare (ignore frame command)))

;;--- Should "gray" the command button, if there is one
(defmethod note-command-disabled ((framem genera-frame-manager) frame command)
  (declare (ignore frame command)))