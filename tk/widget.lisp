;; -*- mode: common-lisp; package: tk -*-
;;
;;				-[]-
;; 
;; copyright (c) 1985, 1986 Franz Inc, Alameda, CA  All rights reserved.
;; copyright (c) 1986-1991 Franz Inc, Berkeley, CA  All rights reserved.
;;
;; The software, data and information contained herein are proprietary
;; to, and comprise valuable trade secrets of, Franz, Inc.  They are
;; given in confidence by Franz, Inc. pursuant to a written license
;; agreement, and may be stored and used only in accordance with the terms
;; of such license.
;;
;; Restricted Rights Legend
;; ------------------------
;; Use, duplication, and disclosure of the software, data and information
;; contained herein by any agency, department or entity of the U.S.
;; Government are subject to restrictions of Restricted Rights for
;; Commercial Software developed at private expense as specified in FAR
;; 52.227-19 or DOD FAR Supplement 252.227-7013 (c) (1) (ii), as
;; applicable.
;;
;; $fiHeader: widget.lisp,v 1.16 92/04/15 11:44:53 cer Exp Locker: cer $

(in-package :tk)

(defun app-create-shell (&rest args
			       &key (application-name 0)
			       (application-class 0)
			       (widget-class (error "Class not specified"))
			       (display (error "Display not specifie"))
			       &allow-other-keys)
  (let* ((class (find-class widget-class))
	 (handle (class-handle class))
	 (arglist (make-arglist-for-class class nil args)))
    (register-address
     (apply #'make-instance
	    class
	    :foreign-address
	    (app_create_shell application-name
			      application-class
			      handle
			      display
			      arglist
			      (truncate (length arglist) 2))
	    :display display
	    args))))

(defun create-widget (name widget-class parent &rest args)
  (apply #'create-widget-1 
	 #'create_widget name widget-class parent 
	 args))

(defun create-managed-widget (name widget-class parent &rest args)
  (apply #'create-widget-1 
	 #'create_managed_widget name widget-class parent 
	 args))


(defun create-widget-1 (fn name widget-class parent &rest args)
  (let* ((class (find-class-maybe widget-class))
	 (handle (class-handle class))
	 (arglist (make-arglist-for-class class parent args)))
    (funcall fn (string-to-char* name )
	     handle
	     parent
	     arglist
	     (truncate (length arglist) 2))))

(defun realize-widget (widget)
  (realize_widget widget))

(defun manage-child (child)
  (manage_child child))

(defun unmanage-child (child)
  (unmanage_child child))

(defun is-managed-p (widget)
    (not (zerop (xt_is_managed widget))))

(defun manage-children (children)
  (manage_children (map '(simple-array (signed-byte 32))
		     #'ff:foreign-pointer-address 
		     children)
		   (length children)))
		     
(defun destroy-widget (widget)
  (destroy_widget widget))

(defun popup (shell)
       (_popup shell 0))

(defun popdown (shell)
       (_popdown shell))

(defun create-popup-shell (name widget-class parent &rest args)
  (let* ((class (find-class-maybe widget-class))
	 (handle (class-handle class))
	 (arglist (make-arglist-for-class class parent args)))
    (create_popup_shell
	     (string-to-char* name)
	     handle
	     parent
	     arglist
	     (truncate (length arglist) 2))))

(defun find-class-maybe (x)
  (if (typep x 'clos::class) x
    (find-class x)))

(defmethod widget-window (widget &optional (errorp t) peek)
  (with-slots (window-cache) widget
    (or window-cache
	(and (not peek)
	     (setf window-cache
	       (let ((id (xt_window widget)))
		 (if (zerop id)
		     (and errorp
			  (error "Invalid window id ~D for ~S" id widget))
		   (intern-object-xid
		    id
		    'window 
		    :display (widget-display widget)))))))))

(defun make-clx-window (display widget)
  (let* ((window-id (xt_window widget)))
    (make-clx-window-from-id display window-id)))

(defun widget-class-of (x)
  (intern-widget-class
   (xtk-widget-widget-class x)))

(defun intern-widget-class (class)
  (find-object-from-address class))


(defmethod initialize-instance :after ((w xt-root-class) 
				       &rest args 
				       &key foreign-address 
				       parent display
				       &allow-other-keys)
  (when (or display parent)
    (setf (slot-value w 'display)
      (or display
	  (object-display parent))))
  (unless foreign-address
    (register-widget
     w
     (progn
       (remf :foreign-address args)
       (setf (foreign-pointer-address w)
	 (apply #'make-widget w args))))))

(defmethod destroy-widget-cleanup ((widget xt-root-class))
  (dolist (cleanup (widget-cleanup-functions widget))
    (apply (car cleanup) (cdr cleanup)))
  ;;--- When we start using gadgets things will be fun!
  (let ((w (widget-window widget nil t)))
    (when w (unregister-xid w)))
  (unintern-widget widget))

(defun intern-widget (widget-address &rest args)
  (unless (zerop widget-address)
    (multiple-value-bind
	(widget newp)
	(apply
	 #'intern-object-address 
	 widget-address
	 (widget-class-of widget-address)
	 args)
      (when newp
	(add-callback widget :destroy-callback #'destroy-widget-cleanup))
      widget)))

(defun register-widget (widget &optional (handle (foreign-pointer-address widget)))
  (register-address widget handle)
  (add-callback widget :destroy-callback #'destroy-widget-cleanup))

(defun unintern-widget (widget)
  (unintern-object-address (foreign-pointer-address widget)))

(defmethod widget-parent (widget)
  (let ((x (xt_parent widget)))
    (and (not (zerop x)) (intern-widget x))))

(def-c-type xt-geometry-mask :unsigned-int)
(def-c-type xt-position :short)
(def-c-type xt-dimension :unsigned-short)

(def-c-type (xt-widget-geometry :in-foreign-space) :struct
  (request-mode xt-geometry-mask)
  (x xt-position)
  (y xt-position)
  (width xt-dimension)
  (height xt-dimension)
  (border-width xt-dimension)
  (sibling xtk-widget)
  (stack-mode :int))

(defconstant xt-geometry-yes 0)
(defconstant xt-geometry-no 1)
(defconstant xt-geometry-almost 2)
(defconstant xt-geometry-done 3)



(defmethod widget-best-geometry (widget &key width height)
  (let ((preferred (make-xt-widget-geometry)))
    (xt_query_geometry
     widget
     (if (or width height)
	 (let ((x (make-xt-widget-geometry)))
	   (when width
	     (setf (xt-widget-geometry-width x) (round width)))
	   (when height
	     (setf (xt-widget-geometry-height x) (round height)))
	   (setf (xt-widget-geometry-request-mode x)
	     (logior
	      (if width x11:cwwidth 0)
	      (if height x11:cwheight 0)))
	   x)
	   0)
     preferred)
    (let ((r (xt-widget-geometry-request-mode preferred)))
      (values
       (xt-widget-geometry-x preferred)
       (xt-widget-geometry-x preferred)
       (xt-widget-geometry-width preferred)
       (xt-widget-geometry-height preferred)
       (xt-widget-geometry-border-width preferred)
       (logtest r x11:cwx)
       (logtest r x11:cwy)
       (logtest r x11:cwwidth)
       (logtest r x11:cwheight)
       (logtest r x11:cwborderwidth)))))

;;--- Should call either XtResizeWidget or XtConfigureWidget

(defun tk::configure-widget (widget &key x y width height 
					 (border-width 
					  (get-values widget :border-width)))
  (xt_configure_widget widget x y width height
		       border-width))


(defun describe-widget (w)
  (dolist (r (class-resources (class-of w)))
    (format t "~S : ~S~%"
	    (resource-name r)
	    (handler-case
		(get-values w (intern (resource-name r) :keyword))
	      (error (c) c "Get-values failed!")))))

(defun set-sensitive (widget value)
  (xtsetsensitive widget (if value 1 0)))
