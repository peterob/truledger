; -*- mode: lisp -*-

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Test code for Trubanc client and server
;;;

(in-package :trubanc-test)

(defvar *test-pathname*
  (or *load-pathname* "~/loom/web/trubanc/lisp/src/tests.lisp"))

(defparameter *www-dir*
  (directory-namestring (merge-pathnames "../www/" *test-pathname*)))

(defun make-test-state (db-dir &rest rest &key dont-erase passphrase port network-p)
  (declare (ignore dont-erase passphrase port network-p))
  (apply #'make-instance 'test-state
         :db-dir db-dir
         rest))        

(defclass test-state ()
  ((db-dir :accessor db-dir
           :initarg :db-dir)
   (port :accessor port
         :initarg :port
         :initform 8081)
   (passphrase :accessor passphrase
               :initarg :passphrase
               :initform "passphrase")
   (server :accessor server
           :initform nil)
   (client :accessor client
           :initform nil)))

(defmethod initialize-instance :after ((ts test-state) &key
                                       dont-erase
                                       (network-p nil))
  (let* ((db-dir (ensure-directory-pathname (db-dir ts)))
         (port (port ts))
         (passphrase (passphrase ts))
         (server-dir (merge-pathnames "serverdb" db-dir))
         (client-dir (merge-pathnames "clientdb" db-dir)))
    (when network-p
      (stop-web-server port))
    (unless dont-erase
      (ignore-errors (recursive-delete-directory server-dir))
      (ignore-errors (recursive-delete-directory client-dir)))
    (setf (server ts) (make-server
                       server-dir passphrase
                       :bankname "Test Bank"
                       :bankurl (format nil "http://localhost:~d/" port))
          (client ts) (make-client client-dir
                                   :test-server (unless network-p (server ts))))
    (when network-p
      (start-test-web-server ts))))

(defmethod start-test-web-server ((ts test-state))
  (trubanc-web-server (server ts) :www-dir *www-dir* :port (port ts)))

(defmethod stop-test-web-server ((ts test-state))
  (stop-web-server (port ts)))

(defmethod login-bank ((ts test-state))
  (let* ((server (server ts))
         (client (client ts))
         (bankid (bankid server))
         (passphrase (passphrase ts)))
    (handler-case (login client passphrase)
      (error ()
        (let ((privkey (decode-rsa-private-key
                        (encode-rsa-private-key (privkey server)))))
          (newuser client
                   :passphrase passphrase
                   :privkey privkey))))
    (handler-case (setbank client bankid)
      (error ()
        (addbank client (bankurl server))
        (let ((balance (getbalance client))
              (tokenid (tokenid server)))
          (loop
             for (acct . bals) in balance
             do
               (unless (equal acct $MAIN)
                 (error "Found non-main acct: ~s" acct))
               (dolist (bal bals)
                 (let ((assetid (balance-assetid bal))
                       (assetname (balance-assetname bal))
                       (amount (balance-amount bal))
                       (formatted-amount (balance-formatted-amount bal)))
                   (assert (equal tokenid assetid))
                   (assert (equal assetname "Test Bank Usage Tokens"))
                   (assert (equal amount "-1"))
                   (assert (equal formatted-amount "-0"))))))))
    (id client)))
  
(defmethod login-user ((ts test-state) passphrase &optional (name passphrase))
  (let ((client (client ts))
        (server (server ts)))
    (handler-case (login client passphrase)
      (error ()
        (newuser client :passphrase passphrase :privkey 512)))
    (handler-case (setbank client (bankid server))
      (error ()
        (handler-case (addbank client (bankurl server) name)
          (error ()
            (let ((id (id client)))
              (login-bank ts)
              (spend client id (tokenid server) "200" nil "Welcome to my bank")
              (login client passphrase)
              (addbank client (bankurl server) name))))))
    (id client)))

(defmethod accept-inbox ((ts test-state) &optional (accept-p t))
  (let* ((client (client ts))
         (inbox (getinbox client))
         (directions))
    (dolist (item inbox)
      (push (make-process-inbox
             :time (inbox-time item)
             :request (if accept-p $SPENDACCEPT $SPENDREJECT)
             :note (format nil "~a ~a"
                           (if accept-p "Accepting" "Rejecting")
                           (or (inbox-msgtime item) (inbox-time item))))
            directions))
    (processinbox client directions)))
             
(defmethod spend-test ((ts test-state) &optional (tokens-p t))
  (declare (ignore tokens-p))
  (let* ((john (prog1 (login-user ts "john") (accept-inbox ts)))
         (bill (prog1 (login-user ts "bill") (accept-inbox ts)))
         (client (client ts))
         (fee (getfees client))
         (fee-asset (fee-assetid fee))
         (fee-amount (fee-amount fee))
         (bill-bals (cdar (getbalance client $MAIN)))
         (bill-token-bal (find fee-asset bill-bals
                               :test #'equal
                               :key #'balance-assetid))
         (bill-tokens (balance-amount bill-token-bal)))
    (spend client john fee-asset "10" nil (strcat john bill))
    (setq bill-bals (cdar (getbalance client $MAIN))
          bill-token-bal (find fee-asset bill-bals
                               :test #'equal
                               :key #'balance-assetid))
    (assert (eql 0 (bccomp (balance-amount bill-token-bal)
                           (bcsub bill-tokens 10 fee-amount)))
            nil
            "Balance mismatch after spend")
    (login-user ts "john")
    (accept-inbox ts)
    (login-user ts "bill")
    (accept-inbox ts)
    (setq bill-bals (cdar (getbalance bill-bals))
          bill-token-bal (find fee-asset bill-bals
                               :test #'equal
                               :key #'balance-assetid))
    (assert (eql 0 (bccomp (balance-amount bill-token-bal)
                           (bcsub bill-tokens 10)))
            nil
            "Balance mismatch after accept")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Copyright 2009 Bill St. Clair
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions
;;; and limitations under the License.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
