;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Package: CLIM-DEMO; Base: 10; Lowercase: Yes -*-

;; $fiHeader: address-book.lisp,v 1.4 91/03/26 12:37:27 cer Exp $

(in-package :clim-demo)

"Copyright (c) 1990 International Lisp Associates.  All rights reserved."

;;; Define a simple CLIM program.  This program maintains a simple address book.
;;; First, we need a minimal address database.

;;; A structure to hold each address
(defclass address ()
    ((name :initarg :name :accessor address-name)
     (address :initarg :address :accessor address-address)
     (number :initarg :number :accessor address-number))
  (:default-initargs :name "Unsupplied" :address "Unsupplied" :number "Unsupplied"))

;;; Database maintenance.
(defun make-address (&key name address number)
  (make-instance 'address :name name :address address :number number))

;;; A support utility.
(defun last-name (name)
  (subseq name (1+ (or (position #\Space name :test #'char-equal :from-end T) -1))))

;;; And a function which operates on the address class.
(defun address-last-name (address)
  (last-name (address-name address)))

;;; A place to keep addresses.
(defvar *addresses* nil)

(defun add-address (address)
  ;; Obviously could deal with multiple address entries with same name
  ;; here, but that's outside the scope of this demo.
  (pushnew address *addresses* :key #'address-name :test #'string-equal)
  (setq *addresses* (sort *addresses* #'string-lessp :key #'address-last-name)))

(progn
  (add-address (make-address :name "Bill York"
			     :address "ILA, Mountain View"
			     :number "415-968-3656"))
  (add-address (make-address :name "Dennis Doughty"
			     :address "ILA, Cambridge"
			     :number "617-576-1151"))
  (add-address (make-address :name "Mark Son-Bell"
			     :address "ILA, Cambridge"
			     :number "617-576-1151"))
  (add-address (make-address :name "Richard Lamson"
			     :address "ILA, San Francisco"
			     :number "415-661-5477")))

;;; --------------------------------
;;; Define the user interface here.
;;;
;;; First, we define a presentation type for address, which enables us to make them
;;; mouse-sensitive.  We define the :printer for the presentation-type to print out just
;;; the personal name of the address entry.

(define-presentation-type address ())

(define-presentation-method present (object (type address) stream view &key)
  (write-string (address-name object) stream))

;;; For translators
(define-presentation-type address-name ())
(define-presentation-type address-address ())
(define-presentation-type address-number ())

;;; Define a method for displaying the "Rolodex" form of entry.  
;;; This will be redisplayed efficiently by CLIM's updating output facility.
;;; [Note that the addition of calls to UPDATING-OUTPUT with specific cache values
;;; could be inserted around each of the fields here to improve the performance if the
;;; amount of information on display became large.  The trade-off would be the relative
;;; speed difference between whatever mechanism would be used to compare unique-ids and 
;;; cache-values (typically EQL) versus the default mechanism for comparing strings
;;; (STRING-EQUAL).]
(defmethod display-address ((address-to-display address) stream)
  (with-slots (name address number) address-to-display
    (with-text-face (stream :italic)
      (write-string "Name: " stream))
    (with-output-as-presentation (stream address-to-display 'address-name)
      (write-string name stream))
    (terpri stream)
    (with-text-face (stream :italic)
      (write-string "Address: " stream))
    (with-output-as-presentation (stream address-to-display 'address-address)
      (write-string address stream))
    (terpri stream)
    (with-text-face (stream :italic)
      (write-string "Number: " stream))
    (with-output-as-presentation (stream address-to-display 'address-number)
      (write-string number stream))))

;;; Define the application-frame for our application
(define-application-frame address-book
			  ()
    ;; This application has two state variables, the currently displayed
    ;; address and the window from which user queries should be read.
    ((current-address :initform nil)
     (interaction-pane )
     (name-pane))
  (:panes
    ((interactor :interactor)
     (menu :command-menu)
     (address :application
	      :incremental-redisplay t
	      :display-function 'display-current-address)
     (names :application
	    :incremental-redisplay t
	    :display-function 'display-names)))
  (:layout
    ((default
       (:column 1
	(:row 1/2
	 (address 1/2)
	 (names :rest))
	(menu :compute)
	(interactor :rest))))))

;;; This is the display-function for the upper-left pane, which specified 
;;; :display-function '(incremental-redisplay-display-function display-current-address).
(defmethod display-current-address ((frame address-book) stream)
  (let ((current-address (slot-value frame 'current-address)))
    (when current-address
       (updating-output (stream :unique-id current-address)
	 (display-address current-address stream)))))

;;; This is the display-function for the upper-right pane, which specified
;;; :display-function '(display-names).
(defmethod display-names ((frame address-book) stream)
  (dolist (address *addresses*)
    ;; PRESENT invokes the :PRINTER for the ADDRESS presentation-type, defined above.
    ;; It also makes each address printed out mouse-sensitive.
    (updating-output (stream :unique-id address)
      (present address 'address :stream stream)
      (terpri stream))))

(define-address-book-command (com-quit-address-book :menu "Quit")
   ()
 (frame-exit *application-frame*))

(define-address-book-command com-select-address
    ((address 'address :gesture :select))
   (setf (slot-value *application-frame* 'current-address) address))

(define-address-book-command (com-new-address :menu "New")
    ()
   (let ((name nil)
	 (address nil)
	 (number nil))
     (let ((stream (frame-query-io *application-frame*)))
       (window-clear stream)
       ;; ACCEPTING-VALUES collects all calls to ACCEPT within its body
       ;; into dialog entries and allows parallel, random editing of the fields.
       ;; In this case, a dialog that looks like:
       ;;  Name: a string
       ;;  Address: a string
       ;;  Number: a string
       ;; is produced, where each "a string" is sensitive and can be edited.
       (accepting-values (stream)
	 (setq name (accept 'string :stream stream :prompt "Name"))
	 (terpri stream)
	 (setq address (accept 'string :stream stream :prompt "Address"))
	 (terpri stream)
	 (setq number (accept 'string :stream stream :prompt "Number")))
       (window-clear stream)
       (add-address (make-address :name name :address address :number number)))))

(define-address-book-command com-delete-address
    ((address 'address :gesture :delete))
   (setf *addresses* (delete address *addresses*)))

(define-address-book-command com-change-address-name
    ((address 'address-name :gesture :select))
  (let ((new-name (accept 'string :stream (frame-query-io *application-frame*)
			  :prompt "New name" :default (address-name address))))
    (setf (address-name address) new-name)
    (setq *addresses* (sort *addresses* #'string-lessp :key #'address-last-name))))

(define-address-book-command com-change-address-address
    ((address 'address-address :gesture :select))
  (let ((new-address (accept 'string :stream (frame-query-io *application-frame*)
			     :prompt "New address" :default (address-address address))))
    (setf (address-address address) new-address)))

(define-address-book-command com-change-address-number
    ((address 'address-number :gesture :select))
  (let ((new-number (accept 'string :stream (frame-query-io *application-frame*)
			    :prompt "New number" :default (address-number address))))
    (setf (address-number address) new-number)))

(defvar *address-books* nil)

(defun address-book (&key reinit root)
  (let ((book (cdr (assoc root *address-books*))))
    (when (or (null book) reinit)
      (multiple-value-bind (left top right bottom)
	  (size-demo-frame root 100 100 500 400)
	(setq book (make-application-frame 'address-book :parent root
					   :left left :top top
					   :right right :bottom bottom)))
      (push (cons root book) *address-books*))
    (run-frame-top-level book)))

(define-demo "Address Book" (address-book :root *demo-root*))
