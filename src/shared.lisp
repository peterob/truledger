; -*- mode: lisp -*-

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Shared by client and server
;;;

(in-package :truledger)

(defun escape (str)
  "Escape a string for inclusion in a message"
  (let ((res "")
        (ptr 0))
    (dotimes (i (length str))
      (let ((char (aref str i)))
        (when (position char "(),:.\\")
          (setq res (strcat res (subseq str ptr i) "\\"))
          (setq ptr i))))
    (strcat res (subseq str ptr))))

(defun simple-makemsg (&rest req)
  "Make an unsigned message"
  (loop
     with msg = "("
     for i from 0
     for value in req
     do
     (when (> i 0) (setq msg (strcat msg ",")))
     (setq msg (strcat msg (escape (string (or value "")))))
     finally
     (return (strcat msg ")"))))

(defun as-string (x)
  (cond ((stringp x) x)
        ((integerp x) (format nil "~a" x))
        (t (error "Can't coerce ~s to a string" x))))

(defmethod makemsg ((parser parser) &rest req)
  "Make an unsigned message from the args."
  (let ((hash (make-hash-table :test 'equal))
        (i -1))
    (dolist (arg req) (setf (gethash (incf i) hash) arg))
    (loop
       with args = (match-pattern parser hash)
       with msg = "("
       with msgval = (getarg $MSG args)
       for k from 0
       for v = (getarg k args)
       do
         (unless v (return (strcat msg ")")))
         (unless (equal msg "(")
           (dotcat msg ","))
         (dotcat msg (if (eq v msgval) (as-string v) (escape (as-string v)))))))

(defun assetid (id scale precision name)
  "Return the id for an asset"
  (sha1 (format nil "~a,~a,~a,~a" id scale precision name)))

(defparameter *patterns* nil)

;; Patterns for non-request data
(defun patterns ()
  (or *patterns*
      (let ((patterns `(;; Customer messages
                        (,$SERVERID . (,$PUBKEY (,$COUPON)))
                        (,$ID . (,$SERVERID ,$ID))
                        (,$BALANCE .
                         (,$SERVERID ,$TIME ,$ASSET ,$AMOUNT (,$ACCT)))
                        (,$OUTBOXHASH .
                         (,$SERVERID ,$TIME ,$COUNT ,$HASH (,$TWOPHASECOMMIT)))
                        (,$BALANCEHASH .
                         (,$SERVERID ,$TIME ,$COUNT ,$HASH (,$TWOPHASECOMMIT)))
                        (,$GETFEES . (,$SERVERID ,$REQ (,$OPERATION)))
                        (,$SETFEES . (,$TIME ,$COUNT))
                        (,$SPEND .
                         (,$SERVERID ,$TIME ,$ID ,$ASSET ,$AMOUNT (,$NOTE)))
                        (,$GETASSET . (,$SERVERID ,$REQ ,$ASSET))
                        (,$ASSET .
                         (,$SERVERID ,$ASSET ,$SCALE ,$PRECISION ,$ASSETNAME))
                        (,$STORAGE . (,$SERVERID ,$TIME ,$ASSET ,$PERCENT))
                        (,$STORAGEFEE . (,$SERVERID ,$TIME ,$ASSET ,$AMOUNT))
                        (,$FRACTION . (,$SERVERID ,$TIME ,$ASSET ,$AMOUNT))
                        (,$REGISTER . (,$SERVERID ,$PUBKEY (,$NAME)))
                        (,$GETREQ . (,$SERVERID))
                        (,$SPENDACCEPT . (,$SERVERID ,$TIME ,$ID (,$NOTE)))
                        (,$SPENDREJECT . (,$SERVERID ,$TIME ,$ID (,$NOTE)))
                        (,$GETOUTBOX .(,$SERVERID ,$REQ))
                        (,$GETBALANCE . (,$SERVERID ,$REQ (,$ACCT) (,$ASSET)))
                        (,$GETINBOX . (,$SERVERID ,$REQ))
                        (,$PROCESSINBOX . (,$SERVERID ,$TIME ,$TIMELIST))
                        (,$STORAGEFEES . (,$SERVERID ,$REQ))
                        (,$GETTIME . (,$SERVERID ,$REQ))
                        (,$COUPONENVELOPE . (,$ID ,$ENCRYPTEDCOUPON))
                        (,$GETVERSION . (,$SERVERID ,$REQ))
                        (,$VERSION . (,$VERSION ,$TIME))
                        (,$WRITEDATA . (,$SERVERID ,$TIME ,$ANONYMOUS ,$KEY ,$DATA))
                        (,$READDATA . (,$SERVERID ,$REQ ,$KEY (,$SIZE)))
                        (,$GRANT . (,$SERVERID ,$TIME ,$ID ,$PERMISSION (,$GRANT)))
                        (,$DENY . (,$SERVERID ,$REQ ,$ID ,$PERMISSION))
                        (,$PERMISSION . (,$SERVERID ,$REQ (,$GRANT)))
                        (,$AUDIT . (,$SERVERID ,$REQ ,$ASSET))
                        (,$OPENSESSION . (,$SERVERID ,$REQ (,$TIMEOUT ,$INACTIVETIME)))
                        (,$CLOSESESSION . (,$SERVERID ,$REQ ,$SESSIONID))
                        (,$BACKUP . (,$REQ :rest))
                        (,$COMMIT . (,$SERVERID ,$TIME))
                        (,$GETFEATURES . (,$SERVERID ,$REQ))
                        (,$FEATURES . (,$SERVERID ,$TIME ,$FEATURES))
                        (,$LASTTRANSACTION . (,$SERVERID ,$REQ))

                        ;; Server signed messages
                        (,$FAILED . (,$MSG ,$ERRMSG))
                        (,$TOKENID . (,$TOKENID))
                        (,$REGFEE . (,$SERVERID ,$TIME ,$ASSET ,$AMOUNT))
                        (,$TRANFEE . (,$SERVERID ,$TIME ,$ASSET ,$AMOUNT))
                        (,$FEE . (,$SERVERID ,$TIME ,$OPERATION ,$ASSET ,$AMOUNT))
                        (,$TIME . (,$ID ,$TIME))
                        (,$INBOX . (,$TIME ,$MSG))
                        (,$REQ . (,$ID ,$REQ))
                        (,$COUPON .
                         (,$SERVERURL ,$COUPON ,$ASSET ,$AMOUNT (,$NOTE)))
                        (,$COUPONNUMBERHASH . (,$COUPON))
                        (,$ATREGISTER . (,$MSG))
                        (,$ATOUTBOXHASH . (,$MSG))
                        (,$ATBALANCEHASH . (,$MSG))
                        (,$ATGETINBOX . (,$MSG))
                        (,$ATBALANCE . (,$MSG))
                        (,$ATSETFEES . (,$MSG))
                        (,$ATSPEND . (,$MSG))
                        (,$ATTRANFEE . (,$MSG))
                        (,$ATFEE . (,$MSG))
                        (,$ATASSET . (,$MSG))
                        (,$ATSTORAGE . (,$MSG))
                        (,$ATSTORAGEFEE . (,$MSG))
                        (,$ATFRACTION . (,$MSG))
                        (,$ATPROCESSINBOX . (,$MSG))
                        (,$ATSTORAGEFEES . (,$MSG))
                        (,$ATSPENDACCEPT . (,$MSG))
                        (,$ATSPENDREJECT . (,$MSG))
                        (,$ATGETOUTBOX . (,$MSG))
                        (,$ATCOUPON . (,$COUPON ,$SPEND))
                        (,$ATCOUPONENVELOPE . (,$MSG))
                        (,$ATWRITEDATA . (,$ID ,$TIME ,$ANONYMOUS ,$KEY))
                        (,$ATREADDATA . (,$ID ,$TIME ,$DATA))
                        (,$ATGRANT . (,$MSG))
                        (,$ATDENY . (,$MSG))
                        (,$ATPERMISSION . (,$MSG))
                        (,$ATAUDIT . (,$MSG))
                        (,$ATOPENSESSION . (,$MSG ,$CIPHERTEXT))
                        (,$CLOSESESSION . (,$MSG))
                        (,$ATBACKUP . (,$REQ))
                        (,$ATCOMMIT . (,$MSG))
                        ))
            (hash (make-hash-table :test 'equal)))
        (loop
           for (key . value) in patterns
           do
             (setf (gethash key hash) value))
        (setq *patterns* hash))))

(defmethod dirhash ((db db) key unpacker &optional newitem removed-names)
  "Return the hash of a directory, KEY, of server-signed messages.
    The hash is of the user messages wrapped by the server signing.
    NEWITEM is a new item or an array of new items, not server-signed.
    REMOVED-NAMES is a list of names in the KEY dir to remove.
    UNPACKER is a function to call with a single-arg, a server-signed
    message. It returns a parsed and matched ARGS hash table whose $MSG
    element is the parsed user message wrapped by the server signing.
    Returns two values, the sha1 hash of the items and the number of items."
  (let ((contents (db-contents db key))
        (items nil))
    (dolist (name contents)
      (unless (member name removed-names :test 'equal)
        (let ((msg (db-get db (append-db-keys key name))))
          (when msg                     ;can be nil from validate-db-update
            (let* ((args (funcall unpacker msg))
                   (req (gethash $MSG args)))
              (unless req
                (error "Directory msg is not a server-wrapped message"))
              (unless (setq msg (get-parsemsg req))
                (error "get-parsemsg didn't find anything"))
              (push msg items))))))
    (when newitem
      (if (stringp newitem)
          (push newitem items)
          (setq items (append items (copy-list newitem)))))
    (setq items (sort (mapcar #'trim items) 'string-lessp))
    (when items
      (let* ((str (apply 'implode "." items))
             (hash (sha1 str)))
        (values hash (length items))))))

(defmethod balancehash ((db db) unpacker balancekey &optional acctbals)
  "Compute the balance hash as two values: hash & count.
   UNPACKER is a function of one argument, a string, representing
   a server-signed message. It returns the unpackaged server message
   BALANCEKEY is the key to the user balance directory.
   ACCTBALS is null or a hash table of hash tables: acct => (assetid => msg)"
  (let* ((hash nil)
         (hashcnt 0)
         (accts (db-contents db balancekey))
         (needsort nil))
    (when acctbals
      (loop
         for acct being the hash-keys of acctbals
         do
           (unless (member acct accts :test 'equal)
             (push acct accts)
             (setq needsort t))))
    (when needsort (setq accts (sort accts 'string-lessp)))
    (loop
       for acct in accts
       for newitems = nil
       for removed-names = nil
       for newacct = (and acctbals (gethash acct acctbals))
       do
         (when newacct
           (loop
              for assetid being the hash-key using (hash-value msg) of newacct
              do
                (push msg newitems)
                (push assetid removed-names)))
         (multiple-value-bind (hash1 cnt)
             (dirhash db (append-db-keys balancekey acct) unpacker
                      newitems removed-names)
           (when hash1
             (setq hash (if hash (strcat hash "." hash1) hash1))
             (incf hashcnt cnt))))
    (when (> hashcnt 1) (setq hash (sha1 hash)))
    (values (or hash "") hashcnt)))

(defun hex-char-p (x)
  "Predicate. True if x is 0-9, a-f, or A-F"
  (check-type x character)
  (let ((code (char-code x)))
    (or (and (>= code #.(char-code #\0))
             (<= code #.(char-code #\9)))
        (and (>= code #.(char-code #\a))
             (<= code #.(char-code #\f)))
        (and (>= code #.(char-code #\A))
             (<= code #.(char-code #\F))))))

(defun coupon-number-p (x)
  "Predicate. True if arg looks like a coupon number."
  (and (stringp x)
       (eql 32 (length x))
       (every 'hex-char-p x)))

(defun id-p (x)
  "Predicate. True if arg looks like an ID."
  (and (stringp x)
       (eql 40 (length x))
       (every 'hex-char-p x)))

(defun fraction-digits (percent)
  "Calculate the number of digits to keep for the fractional balance.
   Add 3 for divide by 365, 2 for percent, 3 more for 1/1000 precision."
  (+ (number-precision percent) 8))

(defun storage-fee (balance baltime now percent digits)
  "Calculate the storage fee.
   BALANCE is the balance.
   BALTIME is the time of the BALANCE, as an integer string.
   NOW is the current time, as an integer string.
   PERCENT is the storage fee rate, in percent/year.
   DIGITS is the precision for the arithmetic.
   Returns two values:
    1) the storage fee
    2) balance - storage-fee"
  (wbp (digits)
    (cond ((eql 0 (bccomp percent 0))
           (values "0" balance))
          (t (let* ((secs-per-year-pct #.(* 60 60 24 365 100))
                    (fee (bcdiv (bcmul balance
                                       percent
                                       (wbp (0) (bcsub now baltime)))
                                secs-per-year-pct)))
               (cond ((> (bccomp fee balance) 0)
                      (setq fee balance)))
               (values fee (bcsub balance fee)))))))

(defun normalize-balance (balance fraction digits)
  "Add together BALANCE & FRACTION, to DIGITS precision.
   Return two values, the integer part and the fractional part."
  (wbp (digits)
    (multiple-value-bind (int frac)
        (split-decimal (bcadd balance fraction))
      (when (and (< (bccomp int 0) 0) (not (eql 0 frac)))
        (setf frac (strcat "-" frac)))
      (values int frac))))

;; Computing costs for the $WRITEDATA request
(defun data-cost (data)
  (if (blankp data)
      0
      (1+ (ceiling (if (integerp data) data (length data)) 4096))))

(defvar *db-dir* "truledger-dbs")

(defun db-dir ()
  (let ((dir *db-dir*))
    (if (functionp dir) (funcall dir) dir)))

(defun (setf db-dir) (dir)
  (setf *db-dir* dir))

;; The directory for the client database
(defun client-db-dir ()
  (fsdb:append-db-keys (db-dir) "clientdb"))

;; The directory for the server database
(defun server-db-dir ()
  (fsdb:append-db-keys (db-dir) "serverdb"))

;;;
;;; Latches - there's probably a standard name for this
;;; Multiple processes can signal a latch.
;;; Only one process waits for it.
;;;

(defstruct latch
  (lock (make-lock "latch"))
  (semaphore (make-semaphore))
  value)

(defun signal-latch (latch)
  (with-lock-grabbed ((latch-lock latch))
    (unless (latch-value latch)
      (setf (latch-value latch) t)
      (signal-semaphore (latch-semaphore latch)))))

(defun wait-on-latch (latch)
  (wait-on-semaphore (latch-semaphore latch))
  (setf (latch-value latch) nil))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Copyright 2009-2010 Bill St. Clair
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
