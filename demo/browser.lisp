;;; -*- Mode: LISP; Syntax: ANSI-Common-lisp; Package: (CLIM-BROWSER :use (CLIM-LISP CLIM)); Base: 10; Lowercase: Yes -*-

(eval-when (compile load eval)
  (defpackage :clim-browser
    (:use :clim-lisp clim)
    (:shadow package)))

(in-package :clim-browser)

;;; Simple extensible browser
;;; Scott McKay

"Copyright (c) 1990, 1991, 1992 Symbolics, Inc.  All rights reserved."

;;; To use the Browser, first choose a browser type and browser subtype from
;;; the ACCEPTING-VALUES pane in the lower right corner. 
;;; 
;;; After you have selected a browser type, use the "Show Graph" command to
;;; specify the root node for the graph.  You can supply more than one root.
;;; The type of the object you supply to "Show Graph" varies with what the
;;; browser type is (for example, when browsing classes you should type in
;;; a class name.)
;;; 
;;; Once there is a graph drawn, there are a number of useful mouse gestures
;;; defined for the nodes in the graph:
;;; 
;;; 
;;; 
;;; 
;;;   inferiors, and replaces them with an ellipsis node (indicated by "...").
;;; 
;;; 
;;; 
;;;   create some sort of "subnode" which contains additional information (for
;;;   example, the slots for a class).
;;; 
;;;   of operations specific to the browser type (for example, when browsing
;;;   classes you might get other class-related commands).
;;;
;;; There are some other options in the ACCEPTING-VALUES pane:
;;; 
;;; 
;;;   should be shared or not.  
;;;
;;; There are also a few command buttons:
;;; 
;;; 
;;; 
;;; 
;;; 
;;; 
;;;   The items it displays are mouse-sensitive.
;;; 
;;;
;;; There are a few additional commands:
;;; 
;;;   are currently two modes, graphical and textual.
;;;
;;; It is pretty obvious how to write your own browser extensions.  Enjoy.

;;--- This presumes that both SAP:>swm>clim>code>draw-arrow.lisp is loaded


;;; Utilities

(defparameter *browser-print-length* 2)
(defparameter *browser-print-level* 2)

(defun false (&rest args)
  (declare (ignore args))
  nil)

(defun true (&rest args)
  (declare (ignore args))
  t)

(defmacro with-browser-io-environment (&body body)
  `(invoke-with-browser-io-environment #'(lambda () ,@body)))

(defun invoke-with-browser-io-environment (continuation)
  (declare (dynamic-extent continuation))
  ;; Heavily truncate the printed result
  (let ((*print-base* 10)
	(*print-radix* nil)	  
	(*print-readably* nil)
	(*print-pretty* nil)
	(*print-length* *browser-print-length*)
	(*print-level* *browser-print-level*)
	(*print-circle* nil)
	(*print-array* nil)
	(*print-escape* t)
	#+Genera (scl:*print-string-length* nil)
	#+Genera (scl:*print-structure-contents* nil))
    (funcall continuation)))

(defmacro centering-line ((&optional stream) &body body)
  `(invoke-centering-line #'(lambda (,stream) ,@body) ,stream))

(defun invoke-centering-line (continuation stream)
  (multiple-value-bind (sx sy) (stream-cursor-position* stream)
    (let ((inside-width (window-inside-width stream))
	  (line-width (bounding-rectangle-width 
			(with-output-to-output-record (stream)
			  (funcall continuation stream)))))
      (stream-set-cursor-position* stream (+ sx (floor (- inside-width line-width) 2)) sy)
      (funcall continuation stream))))


;;; Basic call nodes

;; These are the generic functions that are intended to be specialized
(defgeneric node-object-name (call-node))
(defgeneric display-node (call-node stream))
(defgeneric node-generate-inferior-objects (call-node subtype))
(defgeneric node-any-inferior-objects-p (call-node subtype))
(defgeneric node-arc-drawer (call-node)
  #+Genera (declare (values arc-drawer arc-drawing-options)))


(defclass basic-call-node ()
    ((object :reader node-object :initarg :object)
     (inferiors :accessor node-inferiors :initform nil)
     (superiors :accessor node-superiors :initform nil)
     ;; RECURSES is T iff this node eventually calls itself
     (recurses  :accessor node-recurses  :initform nil)
     (tick :accessor node-tick :initform 0)))
  
(defmethod node-object-name ((node basic-call-node))
  (node-object node))

(defmethod print-object ((node basic-call-node) stream)
  (with-browser-io-environment
    (if *print-escape*
	(print-unreadable-object (node stream :type t :identity t)
	  (write (node-object-name node) :stream stream :escape nil))
        (write (node-object-name node) :stream stream :escape nil))))

;; Propagate ticks up the graph to get proper redisplay.
(defmethod tick-node ((node basic-call-node))
  (labels ((tick (node)
	     (incf (node-tick node))
	     ;; No need to check for recursion since it is the responsibility
	     ;; of the graph generator to do that.
	     (dolist (superior (node-superiors node))
	       (tick superior))))
    (declare (dynamic-extent #'tick))
    (tick node)))

(defparameter *display-node-character-style* '(:sans-serif nil :very-small))
(defmethod display-node :around ((node basic-call-node) stream)
  (updating-output (stream :unique-id node
			   :cache-value (node-tick node))
    (with-text-style (stream *display-node-character-style*)
      (call-next-method node stream))))

(defmethod display-node ((node basic-call-node) stream)
  (with-output-as-presentation (stream node (presentation-type-of node))
    (write (node-object node) :stream stream :escape nil)))

;; Let the "to" node contribute to the drawing of the arc to it.
(defmethod node-arc-drawer ((node basic-call-node))
  (values #'draw-arrow* nil))

(defmethod node-generate-inferior-objects ((node basic-call-node) subtype)
  (declare (ignore subtype))
  nil)

;; Answers the question "will NODE-GENERATE-INFERIOR-OBJECTS return anything?",
;; except that it's allowed to be much faster.  If this returns T, that means
;; NODE-GENERATE-INFERIOR-OBJECTS might return something; if this returns NIL,
;; then NODE-GENERATE-INFERIOR-OBJECTS will definitely not return anything.
(defmethod node-any-inferior-objects-p ((node basic-call-node) subtype)
  (declare (ignore subtype))
  t)

(defun node-eql (n1 n2)
  (eql (node-object n1) (node-object n2)))


;; This is the most basic instantiable sort of call node.
;; Commands and translators are written on this, not on BASIC-CALL-NODE.
(eval-when (compile load eval) (defclass call-node (basic-call-node) ()))

;; CALL-SUBNODEs are a stripped-down version of CALL-NODEs, which mostly
;; means that most commands and translators don't operate on subnodes.
(eval-when (compile load eval) (defclass call-subnode (basic-call-node) ()))

(defmethod node-any-inferior-objects-p ((node call-subnode) type)
  (declare (ignore type))
  nil)

(defmethod node-arc-drawer ((node call-subnode))
  (values #'draw-arrow* '(:line-dashes #(2 2))))


;; Ellipsis nodes
(eval-when (load compile eval)
  (defclass ellipsis-call-node
	  (basic-call-node)
    ((replaced-node :reader ellipsis-node-replaced-node :initarg :replaced-node))))

(proclaim '(inline make-ellipsis-call-node))
(defun make-ellipsis-call-node (object replaced-node)
  (make-instance 'ellipsis-call-node :object object :replaced-node replaced-node))

(defmethod initialize-instance :after ((node ellipsis-call-node) &rest init-options)
  (declare (ignore init-options))
  ;; The inferiors of the ellipsis node are all of the combined inferiors
  ;; of the node we are replacing
  (let ((inferiors nil))
    (dolist (inferior (node-inferiors (ellipsis-node-replaced-node node)))
      (setq inferiors (nconc inferiors (copy-list (node-inferiors inferior)))))
    (setf (node-inferiors node) inferiors))
  node)

(defmethod display-node ((node ellipsis-call-node) stream)
  (with-output-as-presentation (stream node 'ellipsis-call-node)
    (write-string "..." stream)))


;;; Hooks to define a type of browser

(defvar *browser-types* nil)

(defgeneric browser-type-subtypes (type))
(defgeneric browser-type-information (type subtype)
  #+Genera (declare (values node-maker root-node-maker
			    graph-type grapher-args presentation-type options)))

(defmacro define-browser-type (type presentation-type graph-type options &body subtypes)
  #+Genera (declare (zwei:indentation 3 3 4 1))
  (let ((subtype-names (mapcar #'first subtypes)))
    `(progn
       (let ((old (member ',type *browser-types*)))
	 (if old
	     (setf (car old) ',type)
	     (setq *browser-types* (nconc *browser-types* (list ',type)))))
       (defmethod browser-type-subtypes ((type (eql ',type)))
	 ',subtype-names)
       ,@(mapcar 
	   #'(lambda (entry)
	       (destructuring-bind (subtype node-maker root-node-maker grapher-args) entry
		 `(defmethod browser-type-information ((type (eql ',type))
						       (subtype (eql ',subtype)))
		    (values ',node-maker ',root-node-maker
			    ',graph-type ',grapher-args 
			    ',presentation-type ',options))))
	   subtypes))))


;;; Function call browsing

(defclass function-call-node (call-node) ())
  
(proclaim '(inline make-function-call-node))
(defun make-function-call-node (object)
  (make-instance 'function-call-node :object object))

(defmethod node-object-name ((node function-call-node))
  (let ((function (node-object node)))
    #+Genera (if (functionp function) (sys:function-name function) function)
    #-Genera function))

(defmethod display-node ((node function-call-node) stream)
  (labels ((draw (stream)
	     (with-output-as-presentation (stream node 'function-call-node)
	       (present (node-object-name node) 'expression :stream stream))))
    (declare (dynamic-extent #'draw))
    (if (node-recurses node)
	(surrounding-output-with-border (stream :shape :rectangle)
	  (draw stream))
	(draw stream))))

(define-browser-type :function expression :graphical
    ()
  (:callees make-function-call-node function-browser-make-root
	    (:arc-drawer draw-arrow*))
  (:callers make-function-call-node function-browser-make-root
	    (:arc-drawer draw-arrow* :arc-drawing-options (:from-head t :to-head nil))))

(defun function-browser-make-root (object)
  (typecase object
    (function 
      (make-function-call-node object))
    (symbol
      (when (fboundp object)
	(make-function-call-node (fdefinition object))))))

#+Genera
(defmethod node-generate-inferior-objects ((node function-call-node) (type (eql ':callees)))
  (let ((function (node-object node)))
    (typecase function
      (compiled-function
	(let ((callees nil))
	  (si:map-over-compiled-function-callees
	    function
	    #'(lambda (caller callee how)
		(declare (ignore caller))
		(case how
		  ((:function :generic-function)
		   (pushnew (sys:fdefinition callee) callees))
		  (:variable
		    (pushnew callee callees))))
	    :external-references t)
	  (nreverse callees)))
      (flavor:generic-function
	;; Return all the real methods for this generic function
	(loop for method in (sort (flavor:generic-function-methods
				    (sys:generic-function-name function))
				  #'string-lessp
				  :key #'flavor:method-flavor)
	      as function = (unless (and (listp method)
					 (eql (first method) 'flavor:read-instance-variable))
			      (si:valid-function-definition method))
	      when function
		collect function))
      (clos:generic-function
	;; Return all the real methods for this generic function
	(loop for method in (clos-internals::sort-generic-function-methods
			      function
			      (copy-list (clos:generic-function-methods function))
			      :sort :heuristic)
	      as function = (clos:method-function method)
	      when function
		collect function)))))

#+Genera
(defmethod node-generate-inferior-objects ((node function-call-node) (type (eql ':callers)))
  (let ((function (node-object node)))
    (let ((callee-function-name (sys:function-name function)))
      (typecase callee-function-name
	(clos:method
	  (list (clos:method-generic-function callee-function-name)))
	(t
	  (if (and (listp callee-function-name)
		   (eql (car callee-function-name) 'flavor:method))
	      (list (flavor:method-generic callee-function-name))
	      (let ((callers nil))
		(si:map-over-callers
		  (sys:function-name function)
		  #'(lambda (caller how)
		      (case how
			((:function :generic-function :macro)
			 (pushnew (sys:fdefinition caller) callers))
			(:variable
			  (pushnew caller callers))))
		  :called-how '(:function :generic-function :macro :variable))
		(nreverse callers))))))))


;;; CLOS class browsing

(define-presentation-type class ()
  :history t)

#+Genera
(define-presentation-method accept ((type class) stream (view textual-view) &key)
  (find-class
    (completing-from-suggestions (stream :partial-completers '(#\-))
      (map nil #'(lambda (x) 
		   (if (listp x)
		       (suggest (first x) (second x))
		       (suggest (symbol-name x) x)))
	   clos-internals:*all-class-names-aarray*))))

#-Genera
(define-presentation-method accept ((type class) stream (view textual-view) &key default)
  (let* ((class-name (accept 'symbol :stream stream :view view
				     :default (and default (class-name default))
				     :prompt nil))
	 (class (find-class class-name nil)))
    (unless class
      (input-not-of-required-type class-name type))
    class))

(define-presentation-method present (class (type class) stream (view textual-view) &key)
  (prin1 (class-name class) stream))


(defclass class-call-node (call-node) ())

(proclaim '(inline make-class-call-node))
(defun make-class-call-node (object)
  (make-instance 'class-call-node :object object))

(defmethod node-object-name ((node class-call-node))
  (class-name (node-object node)))

(defmethod display-node ((node class-call-node) stream)
  (let ((class (node-object node)))
    (with-output-as-presentation (stream node 'class-call-node)
      (with-output-as-presentation (stream class 'class)
	(write (node-object-name node) :stream stream)))))

(define-browser-type :class class :graphical
    ()
  (:superclasses make-class-call-node clos-browser-make-root
		 (:arc-drawer draw-arrow* :arc-drawing-options (:from-head t :to-head nil)))
  (:subclasses make-class-call-node clos-browser-make-root
	       (:arc-drawer draw-arrow*)))

(defun clos-browser-make-root (object)
  (typecase object
    (class
      (make-class-call-node object))
    (symbol
      (let ((class (find-class object nil)))
	(when class
	  (make-class-call-node class))))))

(defmethod node-generate-inferior-objects ((node class-call-node) (type (eql ':superclasses)))
  (class-direct-superclasses (node-object node)))

(defmethod node-any-inferior-objects-p ((node class-call-node) (type (eql ':superclasses)))
  (not (null (class-direct-superclasses (node-object node)))))

(defmethod node-generate-inferior-objects ((node class-call-node) (type (eql ':subclasses)))
  (class-direct-subclasses (node-object node)))

(defmethod node-any-inferior-objects-p ((node class-call-node) (type (eql ':subclasses)))
  (not (null (class-direct-subclasses (node-object node)))))


(defclass clos-slot-call-subnode (call-subnode) ())

(proclaim '(inline make-clos-slot-call-subnode))
(defun make-clos-slot-call-subnode (class-node slots)
  (let ((subnode (make-instance 'clos-slot-call-subnode :object slots)))
    (setf (node-superiors subnode) (list class-node))
    subnode))

(defmethod node-object-name ((node clos-slot-call-subnode))
  (format nil "Slots of ~S" (node-object-name (first (node-superiors node)))))

(defmethod display-node ((node clos-slot-call-subnode) stream)
  (let ((slots (node-object node)))
    (with-output-as-presentation (stream node 'clos-slot-call-subnode
				  :single-box t)
      (surrounding-output-with-border (stream :shape :rectangle)
	(formatting-table (stream)
	  (dolist (slot slots)
	    (formatting-row (stream)
	      (formatting-cell (stream)
		(present slot 'symbol :stream stream)))))))))


(defclass clos-method-call-subnode (call-subnode) ())

(proclaim '(inline make-clos-method-call-subnode))
(defun make-clos-method-call-subnode (class-node method-list)
  (let ((subnode (make-instance 'clos-slot-call-subnode :object method-list)))
    (setf (node-superiors subnode) (list class-node))
    subnode))

(defmethod node-object-name ((node clos-method-call-subnode))
  (format nil "Methods of ~S" (node-object-name (first (node-superiors node)))))

(defmethod display-node ((node clos-method-call-subnode) stream)
  (let ((methods (node-object node)))
    (with-output-as-presentation (stream node 'clos-method-call-subnode
				  :single-box t)
      (surrounding-output-with-border (stream :shape :rectangle)
	(formatting-table (stream)
	  (dolist (item methods)
	    (formatting-row (stream)
	      (formatting-cell (stream)
		(destructuring-bind (gf method) item
		  (with-output-as-presentation (stream method 'expression
						:allow-sensitive-inferiors nil)
		    (prin1 (clos:generic-function-name gf) stream)))))))))))


;;; Package browsing

(define-presentation-type package ()
  :inherit-from t
  :history t)

#+Genera
(define-presentation-method accept ((type package) stream (view textual-view) &key)
  (completing-from-suggestions (stream :partial-completers '(#\-))
    (map nil #'(lambda (package) 
		 (suggest (package-name package) package))
	 (list-all-packages))))

(define-presentation-method present (package (type package) stream (view textual-view) &key)
  (princ (package-name package) stream))


(defclass package-call-node (call-node) ())
  
(proclaim '(inline make-package-call-node))
(defun make-package-call-node (object)
  (make-instance 'package-call-node :object object))

(defmethod node-object-name ((node package-call-node))
  (package-name (node-object node)))

(defmethod display-node ((node package-call-node) stream)
  (with-output-as-presentation (stream node 'package-call-node)
    (present (node-object node) 'package :stream stream)))

(define-browser-type :package package :graphical
    ()
  (:uses make-package-call-node package-browser-make-root
	 (:arc-drawer draw-arrow* :arc-drawing-options (:from-head t :to-head nil)))
  (:used-by make-package-call-node package-browser-make-root
	    (:arc-drawer draw-arrow*)))

(defun package-browser-make-root (object)
  (typecase object
    (package
      (make-package-call-node object))
    ((or string symbol)
     (let ((package (find-package object)))
       (and package
	    (make-package-call-node package))))))

(defmethod node-generate-inferior-objects ((node package-call-node) (type (eql ':uses)))
  (package-use-list (node-object node)))

(defmethod node-any-inferior-objects-p ((node package-call-node) (type (eql ':uses)))
  (not (null (package-use-list (node-object node)))))

(defmethod node-generate-inferior-objects ((node package-call-node) (type (eql ':used-by)))
  (package-used-by-list (node-object node)))

(defmethod node-any-inferior-objects-p ((node package-call-node) (type (eql ':used-by)))
  (not (null (package-used-by-list (node-object node)))))


(defclass package-symbols-subnode (call-subnode) ())

(proclaim '(inline make-package-symbols-subnode))
(defun make-package-symbols-subnode (package-node symbols)
  (let ((subnode (make-instance 'package-symbols-subnode :object symbols)))
    (setf (node-superiors subnode) (list package-node))
    subnode))

(defmethod node-object-name ((node package-symbols-subnode))
  (format nil "Instance variables of ~S" (node-object-name (first (node-superiors node)))))

(defmethod display-node ((node package-symbols-subnode) stream)
  (let ((symbols (node-object node)))
    (with-output-as-presentation (stream node 'package-symbols-subnode
				  :single-box t)
      (surrounding-output-with-border (stream :shape :rectangle)
	(formatting-table (stream :multiple-columns t)
	  (dolist (symbol symbols)
	    (formatting-row (stream)
	      (formatting-cell (stream)
		(present symbol 'symbol :stream stream)))))))))


;;; File system browsing (how can I resist?)

;; As the object, we have a list of the form (PATHNAME . PROPERTIES)
(defclass filesystem-call-node
	  (call-node)
    ((directory-p :reader filesystem-node-directory-p :initarg :directory-p)))

(proclaim '(inline make-filesystem-call-node))
(defun make-filesystem-call-node (object)
  (destructuring-bind (pathname &rest properties) object
    (let* ((directory-p (getf properties :directory))
	   (pathname (if directory-p
			 (make-pathname :name :wild
					:type :wild
					:version :newest
					:directory (append (pathname-directory pathname) 
							   (list (pathname-name pathname)))
					:defaults pathname)
			 pathname)))
      (make-instance 'filesystem-call-node :object `(,pathname ,@properties)
					   :directory-p directory-p))))

(defmethod node-object-name ((node filesystem-call-node))
  (let ((pathname (first (node-object node))))
    (namestring pathname)))

(defmethod display-node ((node filesystem-call-node) stream)
  (let ((pathname (first (node-object node))))
    (with-output-as-presentation (stream node 'filesystem-call-node)
      (with-output-as-presentation (stream pathname 'pathname)
	(format stream "~A" pathname)))))

(define-browser-type :filesystem pathname :textual
    ()
  (:filesystem make-filesystem-call-node filesystem-browser-make-root
	       nil))

(defun filesystem-browser-make-root (object)
  (when (pathnamep object)
    (let ((pathname (make-pathname :name :wild
				   :type :wild
				   :version :newest
				   :defaults object)))
      (make-instance 'filesystem-call-node :object `(,pathname :directory t)
					   :directory-p t))))

(defmethod node-generate-inferior-objects ((node filesystem-call-node) (type (eql ':filesystem)))
  (when (filesystem-node-directory-p node)
    (let* ((pathname (first (node-object node)))
	   (dirlist (directory-and-properties
		      (make-pathname :name :wild
				     :type :wild
				     :version :newest
				     :defaults pathname))))
      (sort dirlist #'(lambda (x y)
			(if (string-equal (pathname-name x) (pathname-name y))
			    (string-lessp (pathname-type x) (pathname-type y))
			    (string-lessp (pathname-name x) (pathname-name y))))
	    :key #'first))))

(defmethod node-any-inferior-objects-p ((node filesystem-call-node) (type (eql ':filesystem)))
  (filesystem-node-directory-p node))

(defun directory-and-properties (pathname)
  #+Genera (cdr (fs:directory-list pathname))
  #-Genera (mapcar #'list (directory pathname)))


;;; Lisp object browsing

(defclass lisp-object-call-node (call-node) ())

(proclaim '(inline make-lisp-object-call-node))
(defun make-lisp-object-call-node (object)
  (make-instance 'lisp-object-call-node :object object))

;; Kludge to prevent explosions when we click on a node which doesn't
;; have a reasonable printed representation
(defmethod print-object :around ((node lisp-object-call-node) stream)
  (handler-case
      (call-next-method node stream)
    (print-not-readable)))

(defvar *unbound-marker* (list nil))
(defmethod display-node ((node lisp-object-call-node) stream)
  (let ((object (node-object node)))
    (labels ((draw (stream)
	       ;;--- This should produce a more graphical presentation
	       (with-output-as-presentation (stream node 'lisp-object-call-node)
		 (with-browser-io-environment
		   (if (eql object *unbound-marker*)
		       (princ "Unbound" stream)
		       (prin1 object stream))))))
      (declare (dynamic-extent #'draw))
      (if (node-recurses node)
	  (surrounding-output-with-border (stream :shape :rectangle)
	    (draw stream))
	  (draw stream)))))

(define-browser-type :lisp-object expression :graphical
    ()
  (:objects make-lisp-object-call-node lisp-object-browser-make-root
	    (:arc-drawer draw-arrow*)))

(defun lisp-object-browser-make-root (object)
  (make-lisp-object-call-node
    (if (and (listp object)
	     (fboundp (first object)))
	;; Handles both quoted forms and calls to functions
	(eval object)
	(if (symbolp object)
	    (symbol-value object)
	    object))))

(defmethod node-generate-inferior-objects ((node lisp-object-call-node) (type (eql ':objects)))
  (let ((object (node-object node)))
    (cond #+Genera
	  ((si:named-structure-p object)
	   ;; Generate a list of all of the structures slots
	   ;;--- How to arrange for the slot names to be printed?
	   (let* ((description (get (or (and (arrayp object)
					     (si:named-structure-symbol object))
					(and (listp object)
					     (symbolp (car object))
					     (car object)))
				    'si:defstruct-description)))
	     (loop for (slot-name . slot-description)
		       in (si:defstruct-description-slot-alist description)
		   as form = `(,(si:defstruct-slot-description-ref-macro-name slot-description)
			       ',object)
		   collect (eval form))))
	  ;;--- What do we do for INSTANCEP?
	  (#+Genera (si:instancep object)
	   #+excl (typep object 'standard-object)
	   #+Genera (setq object (si:follow-structure-forwarding object))
	   ;;--- How to arrange for the slot names to be printed?
	   ;; This works for Genera Flavors because they are embedded in CLOS
	   (let* ((class (class-of object))
		  (slots (clos:class-slots class)))
	     (loop for slot in slots
		   as slot-name = (clos:slot-definition-name slot)
		   collect (if (slot-boundp object slot-name)
			       (slot-value object slot-name)
			       *unbound-marker*))))
	  ((stringp object) nil)
	  ((arrayp object) (coerce object 'list))
	  ((consp object) object)
	  (t nil))))

(defmethod node-any-inferior-objects-p ((node lisp-object-call-node) (type (eql ':objects)))
  (let ((object (node-object node)))
    (or (consp object)
        ;;--- What do we do for INSTANCEP?
	#+Genera(si:instancep object)
	#+excl (typep object 'standard-object)
	(and (arrayp object)
	     (not (stringp object))))))


;;; The browser itself

#-Silica
(define-application-frame browser ()
    ((graph-type :initform :graphical)
     (browser-type :initform nil)
     (browser-subtype :initform nil)
     (browser-ptype :initform nil)
     (browser-options :initform nil)
     (node-maker :initform #'false)
     (root-node-maker :initform #'false)
     (grapher-args :initform nil)
     (tree-depth :initform 1)
     (merge-duplicate-nodes :initform t)
     (root-nodes :initform nil)
     (all-nodes :initform nil)
     (auto-snapshot :initform t)
     (snapshots :initform nil))
  (:command-definer t)
  (:command-table (browser :inherit-from (accept-values-pane)))
  (:panes
    ((title :title
       :display-after-commands t
       :display-function 'display-title-pane
       :default-text-style '(:sans-serif :bold :large))
     (graph :application
       :display-function 'display-graph-pane
       :display-after-commands t
       :incremental-redisplay t
       :scroll-bars :both)
     (commands :command-menu
       :display-function '(display-command-menu :n-rows 2))
     (interactor :interactor)
     (control-panel :accept-values
       :display-function '(accept-values-pane-displayer
			    :displayer accept-call-graph-options))))
  (:layout
    ((default 
       (:column 1
	(title :compute)
	(graph :rest)
	(:row 1/4
	 (:column :rest
	  (commands 1/4)
	  (interactor :rest))
	 (control-panel 2/5)))))))

#+Silica
(define-application-frame browser ()
  ((graph-type :initform :graphical)
   (browser-type :initform nil)
   (browser-subtype :initform nil)
   (browser-ptype :initform nil)
   (browser-options :initform nil)
   (node-maker :initform #'false)
   (root-node-maker :initform #'false)
   (grapher-args :initform nil)
   (tree-depth :initform 1)
   (merge-duplicate-nodes :initform t)
   (root-nodes :initform nil)
   (all-nodes :initform nil)
   (auto-snapshot :initform t)
   (snapshots :initform nil))
  (:command-definer t)
  (:command-table (browser :inherit-from (clim-internals::accept-values-pane)))
  (:panes
   (title (scrolling ()
		     (realize-pane 'application-pane
			:display-after-commands t
			:display-function 'display-title-pane
			:default-text-style '(:sans-serif :bold :large))))
   (graph (scrolling ()
		     (realize-pane 'application-pane
			:display-function 'display-graph-pane
			:display-after-commands t
			:incremental-redisplay t
			:scroll-bars :both)))
   (commands (realize-pane 'menu-bar
			   :display-function '(display-command-menu :n-rows 2)))
   (interactor (scrolling ()
			  (realize-pane 'interactor-pane
					:height 50)))
   (control-panel (scrolling ()
			     (realize-pane 'application-pane
					   :height 200
				:display-function '(clim-internals::accept-values-pane-displayer
						    :displayer accept-call-graph-options)))))
  (:layout
   (default
       (vertically () graph interactor control-panel))))


  
#+Genera (define-genera-application browser :select-key #\Triangle)
#+Genera (zwei:defindentation (define-browser-command 0 3 1 3 2 1))

(defmethod configure-for-browser-type ((browser browser) type subtype)
  (with-slots (auto-snapshot browser-type browser-subtype
	       node-maker root-node-maker graph-type grapher-args
	       browser-ptype browser-options) browser
    (when auto-snapshot
      (snapshot-current-graph browser))
    (setq browser-type type
	  browser-subtype subtype)
    (multiple-value-bind (maker root-maker gr-type gr-args ptype options)
	(browser-type-information browser-type browser-subtype)
      (setq node-maker maker
	    root-node-maker root-maker
	    graph-type gr-type
	    grapher-args gr-args
	    browser-ptype ptype
	    browser-options options))))

(defmethod initialize-instance :after ((browser browser) &key)
  (with-slots (root-nodes all-nodes) browser
    (setq root-nodes nil
	  all-nodes nil)
    (configure-for-browser-type
      browser
      (first *browser-types*)
      (first (browser-type-subtypes (first *browser-types*))))))

(defmethod display-title-pane ((browser browser) stream)
  (with-slots (root-nodes browser-type browser-subtype) browser
    (if (or (null browser-type) (null root-nodes))
	(centering-line (stream)
	  (format stream "Browser"))
        (updating-output (stream :unique-id 'title
				 :cache-value (list root-nodes browser-type browser-subtype)
				 :cache-test #'equal)
	  (centering-line (stream)
	    (with-browser-io-environment
	      (format stream "~@(~A~) browser: ~(~A~) of ~S~:[~;, etc.~]"
		browser-type browser-subtype
		(node-object-name (first root-nodes))
		(cdr root-nodes))))))))

(defgeneric display-graph-pane-1 (browser type stream))

(defvar *graph-displayer-types* nil)
(defmacro define-graph-displayer (type (browser stream) &body body)
  `(progn
     (pushnew ',type *graph-displayer-types*)
     (defmethod display-graph-pane-1 ((,browser browser) (type (eql ',type)) ,stream)
       ,@body)))

(defun draw-browser-graph (root-nodes node-printer inferior-producer
			   &key (stream *standard-output*)
				(orientation :horizontal)
				(center-nodes nil)
				(merge-duplicates nil)
				(arc-drawer #'draw-line*)
				(arc-drawing-options nil)
				(generation-separation 
				  clim-internals::*default-generation-separation*)
				(within-generation-separation
				  clim-internals::*default-within-generation-separation*)
				node-filter)
  (flet ((inferior-producer (node)
	   (let ((inferiors (funcall inferior-producer node)))
	     (if (null node-filter)
		 inferiors
	         (delete-if-not node-filter inferiors)))))
    (declare (dynamic-extent #'inferior-producer))
    (format-graph-from-roots root-nodes node-printer #'inferior-producer
			     :stream stream
			     :orientation orientation
			     :center-nodes center-nodes
			     :merge-duplicates merge-duplicates
			     :arc-drawer arc-drawer
			     :arc-drawing-options arc-drawing-options
			     :generation-separation generation-separation
			     :within-generation-separation within-generation-separation)))

(define-graph-displayer :graphical (browser stream)
  (with-slots (root-nodes merge-duplicate-nodes browser-options grapher-args) browser
    (updating-output (stream :unique-id root-nodes)
      (apply #'draw-browser-graph root-nodes #'display-node #'node-inferiors
				  :stream stream
				  :orientation :horizontal
				  :merge-duplicates merge-duplicate-nodes
				  :node-filter (getf browser-options :display-filter)
				  grapher-args))))

(define-graph-displayer :textual (browser stream)
  (with-slots (root-nodes browser-options) browser
    (let ((filter (getf browser-options :display-filter)))
      (labels ((display (node stream indentation)
		 (when (or (null filter)
			   (funcall filter node))
		   (fresh-line stream)
		   (dotimes (i indentation)
		     (declare (ignore i))
		     (write-char #\Space stream))
		   (display-node node stream)
		   (dolist (inferior (node-inferiors node))
		     (display inferior stream (+ indentation 2))))))
	(declare (dynamic-extent #'display))
	(updating-output (stream :unique-id root-nodes)
	  (with-end-of-page-action (stream :allow)
	    (with-end-of-line-action (stream :allow)
	      (dolist (node root-nodes)
		(display node stream 0)))))))))

(defmethod display-graph-pane ((browser browser) stream)
  (with-slots (root-nodes graph-type) browser
    (when root-nodes
      (display-graph-pane-1 browser graph-type stream))))

(defmethod generate-call-graph ((browser browser) nodes
				&optional (depth (slot-value browser 'tree-depth)))
  (with-slots (browser-subtype) browser
    (when nodes
      (let ((generated nil))
	(labels 
	  ((collect-inferiors (node parent-node depth)
	     ;; Disallow direct recursion in a simple-minded way
	     (when (and (plusp depth)
			(not (eql node parent-node)))
	       (let ((places nil)
		     (inferior-objects
		       (filter-generated-objects
			 browser
			 (node-generate-inferior-objects node browser-subtype))))
		 (when inferior-objects
		   (setq generated t)		;we generated something
		   ;; Use this hairy DO stuff to detect dotted lists
		   (do ((place inferior-objects (cdr place)))
		       (())
		     (when (null place) (return nil))
		     (let* ((object (if (consp place) (car place) place))
			    (inferior-node
			      (find-node-for-object browser object)))
		       (cond ((member place places)
			      ;; Beware of circular lists
			      (setf (node-recurses node) t)
			      (return nil))
			     (t
			      (push place places)))
		       (cond ((node-recurses-p browser node inferior-node)
			      (setf (node-recurses node) t))
			     (t
			      (unless (member node (node-superiors inferior-node))
				(setf (node-superiors inferior-node)
				      (nconc (node-superiors inferior-node) (list node))))
			      (unless (member inferior-node (node-inferiors node)
					      :test #'node-eql)
				(setf (node-inferiors node)
				      (nconc (node-inferiors node) (list inferior-node))))))
		       ;; Recursively collect inferiors for these nodes
		       (collect-inferiors inferior-node node (1- depth))
		       (unless (consp place) (return nil)))))))))
	  (declare (dynamic-extent #'collect-inferiors))
	  (dolist (node nodes)
	    (collect-inferiors node nil depth)))
	generated))))

;; Find or intern a new node.
(defmethod find-node-for-object ((browser browser) object &key (test #'eql))
  (with-slots (all-nodes node-maker) browser
    (dolist (node all-nodes)
      (when (funcall test object (node-object node))
	(return-from find-node-for-object node)))
    (let ((node (funcall node-maker object)))
      (setq all-nodes (nconc all-nodes (list node)))
      node)))

(defmethod node-recurses-p ((browser browser) node inferior)
  (with-slots (all-nodes) browser
    (or (eql node inferior)			;quick test often succeeds
	(let ((mark-table 
		#+Genera (scl:make-hash-table :size (length all-nodes) :number-of-values 0)
		#-Genera (make-hash-table :size (length all-nodes))))
	  (labels ((recurses (inferiors)
		     (when (member node inferiors)
		       (return-from node-recurses-p t))
		     (dolist (inferior inferiors)
		       (unless (gethash inferior mark-table)
			 (setf (gethash inferior mark-table) t)
			 (recurses (node-inferiors inferior))))))
	    (declare (dynamic-extent #'recurses))
	    (setf (gethash node mark-table) t)
	    (setf (gethash inferior mark-table) t)
	    (recurses (node-inferiors inferior))
	    nil)))))

;; Given a generator, create the call graph for a node.
(defmethod filter-generated-objects ((browser browser) objects)
  (with-slots (browser-options) browser
    (let ((predicate (getf browser-options :object-filter)))
      (if (null predicate)
	  objects
	  (delete-if-not predicate objects)))))

(defmethod generate-upward-call-graph ((browser browser) inferior-node subtype)
  (let ((superior-objects
	  (filter-generated-objects
	    browser
	    (node-generate-inferior-objects inferior-node subtype))))
    (when superior-objects
      (dolist (object superior-objects)
	(let ((node (find-node-for-object browser object)))
	  (cond ((node-recurses-p browser node inferior-node)
		 (setf (node-recurses node) t))
		(t
		 (unless (member node (node-superiors inferior-node))
		   (setf (node-superiors inferior-node)
			 (nconc (node-superiors inferior-node) (list node))))
		 (unless (member inferior-node (node-inferiors node)
				 :test #'node-eql)
		   (setf (node-inferiors node)
			 (nconc (node-inferiors node) (list inferior-node))))))))
      (recompute-root-nodes browser)
      t)))

(defmethod recompute-root-nodes ((browser browser))
  (with-slots (all-nodes root-nodes) browser
    (loop for node in all-nodes
	  when (null (node-superiors node))
	    collect node into new-roots
	  finally (unless (node-set-equal new-roots root-nodes)
		    (setq root-nodes new-roots)))))

(defun node-set-equal (nodes1 nodes2)
  (let ((l1 (length nodes1))
	(l2 (length nodes2)))
    (and (= l1 l2)
	 (let ((mark-table
		 #+Genera (scl:make-hash-table :size l1 :number-of-values 0)
		 #-Genera (make-hash-table :size l1)))
	   (dolist (node nodes1)
	     (setf (gethash (node-object node) mark-table) t))
	   (every #'(lambda (node) (gethash (node-object node) mark-table))
		  nodes2)))))

(defmethod accept-call-graph-options ((browser browser) stream)
  (with-slots (browser-type browser-subtype tree-depth
	       merge-duplicate-nodes auto-snapshot browser-options 
	       root-nodes root-node-maker all-nodes) browser
    (flet ((accept (type default prompt query-id)
	     (fresh-line stream)
	     (accept type
		     :stream stream :default default
		     :query-identifier query-id :prompt prompt)))
      (declare (dynamic-extent #'accept))
      (multiple-value-bind (new-type ignore type-changed)
	  (accept `(member ,@*browser-types*) (or browser-type (first *browser-types*))
		  "Browser type" 'type)
	(declare (ignore ignore))
	(let* ((sub-ptype
		 (browser-type-subtypes new-type))
	       (new-subtype
		 (accept `(member ,@sub-ptype)
			 (if type-changed (first sub-ptype) browser-subtype)
			 "Browser subtype" 'subtype))
	       (new-depth
		 (accept '(integer 1 10) tree-depth
			 "Starting depth" 'depth))
	       (new-merge
		 (accept 'boolean merge-duplicate-nodes
			 "Merge duplicate nodes" 'merge))
	       (new-auto-snapshot
		 (accept 'boolean auto-snapshot
			 "Automatic snapshots" 'auto-snapshot)))
	  (let ((additional-dialog (getf browser-options :additional-browser-options)))
	    (when additional-dialog
	      (funcall additional-dialog browser stream)))
	  (setq tree-depth new-depth
		merge-duplicate-nodes new-merge
		auto-snapshot new-auto-snapshot)
	  (when (or (not (eql new-type browser-type))
		    (not (eql new-subtype browser-subtype)))
	    (configure-for-browser-type browser new-type new-subtype)
	    (when root-nodes
	      (loop for node in root-nodes
		    as new-node = (funcall root-node-maker (node-object node))
		    when new-node
		      collect new-node into new-root-nodes
		    finally
		      (setq root-nodes new-root-nodes)
		      ;; ALL-NODES and ROOT-NODES must not be EQ lists...
		      (setq all-nodes (copy-list root-nodes))))
	    ;; Regenerate and redisplay the call graph
	    (generate-call-graph browser root-nodes)
	    (redisplay-frame-pane *application-frame* 'graph :force-p t)))))))


;;; Browser commands

(define-browser-command (com-show-graph :name t :menu t)
    ((objects (with-slots (browser-ptype) *application-frame*
		`(or ,browser-ptype (sequence ,browser-ptype) call-node))
	      :prompt "the name of an object"
	      :default nil))
  (with-slots (auto-snapshot root-node-maker root-nodes all-nodes) *application-frame*
    (when auto-snapshot
      (snapshot-current-graph *application-frame*))
    (if (typep objects 'call-node)
	(setq root-nodes (list (funcall root-node-maker (node-object objects))))
        (loop for object in (if (atom objects) (list objects) objects)
	      as new-node = (funcall root-node-maker object)
	      when new-node
		collect new-node into new-root-nodes
	      finally (setq root-nodes new-root-nodes)))
    ;; ALL-NODES and ROOT-NODES must not be EQ lists...
    (setq all-nodes (copy-list root-nodes))
    (window-clear (get-frame-pane *application-frame* 'graph))
    (generate-call-graph *application-frame* root-nodes)
    (redisplay-frame-pane *application-frame* 'graph :force-p t)))

(define-gesture-name :show-graph :button :left :modifiers (:shift))

(define-presentation-to-command-translator show-graph
    (call-node com-show-graph browser
     :gesture :show-graph
     :tester ((object)
	      (presentation-typep
		(node-object object) (slot-value *application-frame* 'browser-ptype))))
    (object)
  (list (node-object object)))

(define-browser-command (com-decache :menu t) ()
  (with-slots (root-nodes all-nodes) *application-frame*
    (setq root-nodes nil
	  all-nodes nil)
    (window-clear (get-frame-pane *application-frame* 'graph))))

(define-browser-command (com-redisplay :menu t) ()
  (window-clear (get-frame-pane *application-frame* 'graph))
  (redisplay-frame-pane *application-frame* 'graph :force-p t))

(define-browser-command (com-hardcopy-graph :name t :menu "Hardcopy")
    (&key (file 'pathname
	   :default (make-pathname :name "GRAPH-HARDCOPY"
				   :type "PS"
				   :defaults (user-homedir-pathname)
				   :case :common)
	   :documentation "File in which to put the PostScript result")
	  (orientation '(member :landscape :portrait)
	   :default :portrait
	   :documentation "Orientation to use on the paper"))
  (with-slots (browser-subtype root-nodes) *application-frame*
    (with-open-file (file-stream file :direction :output)
      (with-output-to-postscript-stream (stream file-stream 
					 :orientation orientation
					 :multi-page t)
	(with-text-style (stream '(:sans-serif :bold :large))
	  (display-title-pane *application-frame* stream))
	(terpri stream)
	(terpri stream)
	(display-graph-pane *application-frame* stream)))))

(define-browser-command (com-set-graph-type :name t)
    ((type `(member ,@*graph-displayer-types*)))
  (with-slots (graph-type) *application-frame*
    (unless (eql type graph-type)
      (setq graph-type type)
      (redisplay-frame-pane *application-frame* 'graph :force-p t))))

(define-browser-command com-show-node-inferiors
    ((node 'call-node :prompt "node to show inferiors for"))
  (when (generate-call-graph *application-frame* (list node) 1)
    (tick-node node)))

(define-presentation-to-command-translator show-node-inferiors
   (call-node com-show-node-inferiors browser
    :gesture :select
    :tester ((object)
	     (node-any-inferior-objects-p 
	       object (slot-value *application-frame* 'browser-subtype))))
   (object)
  (list object))

(define-browser-command com-hide-node-inferiors
    ((node 'call-node :prompt "node to hide inferiors of"))
  (when (node-inferiors node)
    (setf (node-inferiors node) nil)
    (tick-node node)))

(define-presentation-to-command-translator hide-node-inferiors
    (call-node com-hide-node-inferiors browser
     :gesture :describe
     :tester ((object)
	      (not (null (node-inferiors object)))))
    (object)
  (list object))

(define-browser-command com-delete-node
    ((node 'call-node :prompt "node to delete"))
  (when (node-superiors node)
    (dolist (superior (node-superiors node))
      (setf (node-inferiors superior) (delete node (node-inferiors superior))))
    (tick-node node)))

(define-presentation-to-command-translator delete-node
    (call-node com-delete-node browser
     :gesture :describe
     :tester ((object) (and (null (node-inferiors object))
			    (not (null (node-superiors object))))))
    (object)
  (list object))

(define-browser-command com-show-node-superiors
    ((node 'call-node
	   :prompt "node to show superiors for"))
  (with-slots (browser-type browser-subtype) *application-frame*
    (let* ((subtypes (browser-type-subtypes browser-type))
	   (subtype (block find-subtype
		      (dolist (subtype subtypes)
			(unless (eql browser-subtype subtype)
			  (return-from find-subtype subtype))))))
      (when (and subtype
		 (generate-upward-call-graph *application-frame* node subtype))
	(tick-node node)))))

(define-presentation-to-command-translator show-node-superiors
    (call-node com-show-node-superiors browser
     :gesture nil
     :menu t)
    (object)
  (list object))

;; Given a node, replace it by another one which contains the inferiors of
;; all of its inferiors (i.e., splice out the intermediates so that the
;; graph takes up less space).
(define-browser-command com-ellipsize-node
    ((node 'call-node :prompt "node to ellipsize"))
  (with-slots (all-nodes) *application-frame*
    (let ((ellipsis (make-ellipsis-call-node (node-object-name node) node)))
      ;; Dike out all references to the ellipsized node
      (dolist (n all-nodes)
	(nsubstitute ellipsis node (node-inferiors n)))
      (nsubstitute ellipsis node all-nodes)
      (incf (node-tick node))
      (tick-node ellipsis))))

(define-presentation-to-command-translator ellipsize-node
    ((or call-node ellipsis-call-node) com-ellipsize-node browser
     :gesture :delete)
    (object)
  (list object))

(define-browser-command com-unellipsize-node
    ((ellipsis 'ellipsis-call-node :prompt "node to unellipsize" :gesture :select))
  (with-slots (all-nodes) *application-frame*
    (let ((node (ellipsis-node-replaced-node ellipsis)))
      ;; Replace all references to the ellipsized node
      (dolist (n all-nodes)
	(nsubstitute node ellipsis (node-inferiors n)))
      (nsubstitute node ellipsis all-nodes)
      (tick-node node))))


;;; Snapshotting

(defclass snapshot ()
	  ((graph-type :initarg :graph-type :accessor snapshot-graph-type :initform nil)
	   (browser-type :initarg :browser-type :accessor snapshot-browser-type :initform nil)
	   (browser-subtype :initarg :browser-subtype :accessor snapshot-browser-subtype :initform nil)
	   (browser-ptype :initarg :browser-ptype :accessor snapshot-browser-ptype :initform nil)
	   (browser-options :initarg :browser-options :accessor snapshot-browser-options :initform nil)
	   (node-maker :initarg :node-maker :accessor snapshot-node-maker :initform nil)
	   (root-node-maker :initarg :root-node-maker :accessor snapshot-root-node-maker :initform nil)
	   (grapher-args :initarg :grapher-args :accessor snapshot-grapher-args :initform nil)
	   (tree-depth :initarg :tree-depth :accessor snapshot-tree-depth :initform nil)
	   (merge-duplicate-nodes :initarg :merge-duplicate-nodes :accessor snapshot-merge-duplicate-nodes
				  :initform nil)
	   (root-nodes :initarg :root-nodes :accessor snapshot-root-nodes :initform nil)
	   (all-nodes :initarg :all-nodes :accessor snapshot-all-nodes :initform nil)))

(defun make-snapshot (&rest x)
  (apply #'make-instance 'snapshot x))

(define-presentation-type snapshot (&optional snapshots))

(define-presentation-method accept ((type snapshot) stream (view textual-view) &key)
  (values
    (with-browser-io-environment
      (completing-from-suggestions (stream)
	(dolist (snapshot snapshots)
	  (suggest (format nil "~:(~A~) ~:(~A~) ~S"
		     (snapshot-browser-type snapshot)
		     (snapshot-browser-subtype snapshot)
		     (mapcar #'node-object-name (snapshot-root-nodes snapshot)))
		   snapshot))))))

(define-presentation-method present (snapshot (type snapshot) stream (view textual-view) &key)
  (with-browser-io-environment
    (format stream "~:(~A~) ~:(~A~) ~S"
      (snapshot-browser-type snapshot)
      (snapshot-browser-subtype snapshot)
      (mapcar #'node-object-name (snapshot-root-nodes snapshot)))))

(defmethod snapshot-current-graph ((browser browser))
  (with-slots (graph-type browser-type browser-subtype
	       browser-ptype browser-options node-maker
	       root-node-maker grapher-args tree-depth
	       merge-duplicate-nodes root-nodes all-nodes snapshots) browser
    (let ((snapshot (make-snapshot :graph-type graph-type
				   :browser-type browser-type
				   :browser-subtype browser-subtype
				   :browser-ptype browser-ptype
				   :browser-options (copy-list browser-options)
				   :node-maker node-maker
				   :root-node-maker root-node-maker
				   :grapher-args grapher-args
				   :tree-depth tree-depth
				   :merge-duplicate-nodes merge-duplicate-nodes
				   :root-nodes (copy-list root-nodes)
				   :all-nodes (copy-list all-nodes))))
      (flet ((snapshot-equal (s1 s2)
	       (and (eql (snapshot-browser-type s1) (snapshot-browser-type s2))
		    (eql (snapshot-browser-subtype s1) (snapshot-browser-subtype s2))
		    (equal (snapshot-root-nodes s1) (snapshot-root-nodes s2)))))
	(declare (dynamic-extent #'snapshot-equal))
	(let ((old-snapshot (member snapshot snapshots :test #'snapshot-equal)))
	  (if old-snapshot
	      (setf (car old-snapshot) snapshot)
	      (setq snapshots (nconc snapshots (list snapshot)))))))))

(define-browser-command (com-snapshot-graph :menu "Snapshot") ()
  (snapshot-current-graph *application-frame*))

(define-browser-command (com-show-snapshots :menu t) ()
  (with-slots (snapshots) *application-frame*
    (dolist (snapshot snapshots)
      (fresh-line)
      (present snapshot 'snapshot))))

(define-browser-command (com-recover-snapshot :menu t)
    ((snapshot (with-slots (snapshots) *application-frame*
		 `(snapshot ,snapshots))
	       :prompt "snapshot to recover"))
  (with-slots (browser-type browser-subtype root-nodes graph-type
	       browser-ptype browser-options node-maker
	       root-node-maker grapher-args tree-depth
	       merge-duplicate-nodes all-nodes) *application-frame*
    (unless (and (eql browser-type (snapshot-browser-type snapshot))
		 (eql browser-subtype (snapshot-browser-subtype snapshot))
		 (equal root-nodes (snapshot-root-nodes snapshot)))
      (setq graph-type (snapshot-graph-type snapshot)
	    browser-type (snapshot-browser-type snapshot)
	    browser-subtype (snapshot-browser-subtype snapshot)
	    browser-ptype (snapshot-browser-ptype snapshot)
	    browser-options (copy-list (snapshot-browser-options snapshot))
	    node-maker (snapshot-node-maker snapshot)
	    root-node-maker (snapshot-root-node-maker snapshot)
	    grapher-args (snapshot-grapher-args snapshot)
	    tree-depth (snapshot-tree-depth snapshot)
	    merge-duplicate-nodes (snapshot-merge-duplicate-nodes snapshot)
	    root-nodes (copy-list (snapshot-root-nodes snapshot))
	    all-nodes (copy-list (snapshot-all-nodes snapshot)))
      (redisplay-frame-pane *application-frame* 'graph :force-p t))))

(define-presentation-to-command-translator recover-snapshot
    (snapshot com-recover-snapshot browser
     :gesture :select)
    (object)
  (list object))

(define-browser-command com-remove-snapshot
    ((snapshot 'snapshot :prompt "snapshot to remove" :gesture :delete))
  (with-slots (snapshots) *application-frame*
    (setq snapshots (delete snapshot snapshots))))


;;; Less general browser commands, mostly pertaining to subnodes

(define-browser-command com-remove-subnode
    ((subnode 'call-subnode :prompt "subnode to remove" :gesture :delete))
  (with-slots (all-nodes) *application-frame*
    (let ((node (first (node-superiors subnode))))
      (setf (node-inferiors node) (delete subnode (node-inferiors node)))
      (setq all-nodes (delete subnode all-nodes))
      (tick-node subnode))))

(defun subnode-object-present-in-node (node object &key (test #'eql))
  (dolist (subnode (node-inferiors node))
    (when (and (typep subnode 'call-subnode)
	       (funcall test object (node-object subnode)))
      (return-from subnode-object-present-in-node t)))
  nil)

(define-gesture-name :subnode-1 :button :left   :modifiers (:control :meta))
(define-gesture-name :subnode-2 :button :middle :modifiers (:control :meta))

(define-browser-command com-show-clos-slots
    ((class-node 'class-call-node
      :prompt "class node to show slots for" :gesture :subnode-1))
  (let* ((class (node-object class-node))
	 (slots (sort (mapcar #'clos:slot-definition-name (clos:class-direct-slots class))
		      #'string-lessp)))
    (when (and slots
	       (not (subnode-object-present-in-node class-node slots :test #'equal)))
      (let ((subnode (make-clos-slot-call-subnode class-node slots)))
	(push subnode (node-inferiors class-node))
	(tick-node subnode)))))

(define-browser-command com-show-clos-methods
    ((class-node 'class-call-node
      :prompt "class node to show methods for" :gesture :subnode-2))
  (let* ((class (node-object class-node))
	 (methods (clos:specializer-direct-methods class))
	 (method-list
	   (loop for method in methods
		 collect (list (clos:method-generic-function method) method))))
    (setq method-list (sort method-list #'string-lessp
			    :key #'(lambda (item)
				     (let ((name (clos:generic-function-name (first item))))
				       (if (listp name) (second name) name)))))
    (when (and method-list
	       (not (subnode-object-present-in-node class-node method-list
						    :test #'equal)))
      (let ((subnode (make-clos-method-call-subnode class-node method-list)))
	(push subnode (node-inferiors class-node))
	(tick-node subnode)))))


(define-browser-command com-show-exported-symbols
    ((package-node 'package-call-node
      :prompt "package node to show exported symbols of" :gesture :subnode-1))
  (let ((package (node-object package-node))
	symbols)
    (do-external-symbols (symbol package)
      (when (eql (symbol-package symbol) package)
	(push symbol symbols)))
    (setq symbols (sort symbols #'string-lessp :key #'symbol-name))
    (when (and symbols
	       (not (subnode-object-present-in-node package-node symbols :test #'equal)))
      (let ((subnode (make-package-symbols-subnode package-node symbols)))
	(push subnode (node-inferiors package-node))
	(tick-node subnode)))))
