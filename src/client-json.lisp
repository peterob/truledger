; -*- mode: lisp -*-

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; The Truledger JSON webapp server
;;;
;;; See www/docs/json.txt (http://truledger.com/doc/json.txt) for spec.
;;;

(in-package :truledger-json)

;; Called from do-truledger-json in server-web.lisp
;; Returns a JSON string.
(defun json-server ()
  (let* ((client (make-client (client-db-dir))))
    (let* ((res (catch 'error-return
                  (unwind-protect
                       (handler-case
                           (json-server-internal client)
                         (error (c)
                           (json-error "~a" c)))
                    (finalize client))))
           (str (ignore-errors (json:encode-json-to-string res))))
      (or str
          (json:encode-json-to-string
           (catch 'error-return
             (json-error "Unencodable result: ~s" res)))))))

(defun json-error (format-string &rest format-args)
  (throw 'error-return
    `(("@type" . "error")
      ("message" . ,(apply #'format nil format-string format-args)))))

(defparameter *json-commands*
  '("newuser"
    "getprivkey"
    "login"
    "logout"
    "current-user"
    "user-pubkey"
    "getserver"
    "getservers"
    "addserver"
    "setserver"
    "currentserver"
    "privkey-cached?"
    "cache-privkey"
    "getcontact"
    "getcontacts"
    "addcontact"
    "deletecontact"
    "sync-contacts"
    "getasset"
    "getassets"
    "addasset"
    "getfees"
    "getbalance"
    "getbalances"
    "getrawbalances"
    "getfraction"
    "getfractions"
    "getrawfractions"
    "getstoragefee"
    "getstoragefees"
    "spend"
    "spendreject"
    "ishistoryenabled?"
    "sethistoryenabled"
    "gethistorytimes"
    "gethistoryitems"
    "removehistoryitems"
    "getinbox"
    "processinbox"
    "storagefees"
    "getoutbox"
    "redeem"
    "getversion"
    "getpermissions"
    "getgrantedpermissions"
    "grant"
    "deny"
    "audit"))

(defparameter *json-dispatch-table* nil)
(defparameter *last-json-commands* nil)

(defun json-dispatch-table ()
  (if (eq *json-commands* *last-json-commands*)
      *json-dispatch-table*
      (let ((hash (make-hash-table :test #'equal :size (length *json-commands*))))
        (mapc
         (lambda (command)
           (setf (gethash command hash)
                 (intern (format nil "JSON-~a" (string-upcase command))
                         :truledger-json)))
         *json-commands*)
        (prog1
            (setf *json-dispatch-table* hash)
          (setf *last-json-commands* *json-commands*)))))

(defun get-json-command-function (command)
  (or (gethash command (json-dispatch-table))
      (json-error "Unknown command: ~a" command)))

(defun alistp (x)
  (loop
     (when (null x) (return t))
     (unless (listp x) (return nil))
     (let ((elt (pop x)))
       (unless (and (listp elt) (atom (car elt)) (atom (cdr elt)))
         (return nil)))))

(defun json-server-internal (client)
  client
  (let* ((json (or (parm "eval") (json-error "Missing eval string")))
         (form (json:decode-json-from-string json)))
    (unless (and (listp form)
                 (stringp (first form))
                 (listp (cdr form))
                 (alistp (second form))
                 (null (cddr form)))
      (json-error "Eval form must be [command,{arg:value,...}]"))
    (funcall (get-json-command-function (first form)) client (second form))))

(defun assoc-json-value (key alist)
  (cdr (assoc key alist :test #'string-equal)))

(defmacro with-json-args (lambda-list args-alist &body body)
  (let ((args-var (gensym "ARGS")))
    `(let ((,args-var ,args-alist))
       (let ,(loop for var-spec in lambda-list
                for var = (if (listp var-spec) (first var-spec) var-spec)
                for default = (and (listp var-spec) (second var-spec))
                for val-form = `(assoc-json-value
                                 ,(string-downcase (string var)) ,args-var)
                collect `(,var ,(if default
                                    `(or ,val-form ,default)
                                    val-form)))
         ,@body))))

(defun parse-proxy (proxy)
  (check-type proxy (or null string))
  (unless (blankp proxy)
    (let ((colon-pos (position #\: proxy :from-end t)))
      (unless colon-pos
        (json-error "Proxy must be host:port"))
      (let ((host (subseq proxy 0 colon-pos))
            (port (subseq proxy (1+ colon-pos))))
        (unless (ignore-errors
                  (setf port (parse-integer port)))
          (json-error "Proxy port not an integer: ~s" proxy))
        (when (string-equal host "localhost")
          (setf host "127.0.0.1"))
        (list host port)))))

(defun ensure-string (var name &optional optionalp)
  (unless (or (and optionalp (null var))
              (stringp var))
    (json-error "~a must be a string" name)))

(defun ensure-integer (var name &optional optionalp)
  (unless (or (and optionalp (null var))
              (integerp var))
    (json-error "~a must be an integer" name)))

(defun json-newuser (client args)
  (with-json-args (passphrase) args
    (unwind-protect
         (json-newuser-internal client passphrase args)
      (when (stringp passphrase)
        (destroy-password passphrase)))))

(defun json-newuser-internal (client passphrase args)
  (with-json-args (keysize name privkey fetch-privkey? url coupon proxy)
      args
    (ensure-string passphrase "passphrase")
    (ensure-integer keysize "keysize" t)
    (ensure-string name "name" t)
    (ensure-string privkey "privkey" t)
    (ensure-string url "url" t)
    (ensure-string coupon "coupon" t)
    (ensure-string proxy "proxy" t)
    (when (cond (keysize (or privkey fetch-privkey?))
                (privkey fetch-privkey?)
                ((not fetch-privkey?)
                 (json-error
                  "One of keysize, privkey, and fetch-privkey? must be included")))
      (json-error
       "Only one of keysize, privkey, and fetch-privkey? may be included"))
    (when (and url coupon)
      (error "Only one of url and coupon may be included"))
    (when (passphrase-exists-p client passphrase)
      (json-error "There is already a client account for passphrase"))
    (when proxy
      (setf proxy (parse-proxy proxy)))
    (when fetch-privkey?
      (unless url
        (json-error "url required to fetch private key from server"))
      (verify-server client url nil proxy)
      (when fetch-privkey?
        (handler-case
            (setf privkey (fetch-privkey client url passphrase
                                         :http-proxy proxy))
          (error (c)
            (json-error "Error fetching private key from ~a: ~a"
                        url c)))))
    (cond ((and privkey url)
           ;; Make sure we've got an account.
           (verify-private-key client privkey passphrase url proxy))
          ((not coupon)
           (when (server-db-exists-p)
             (json-error "Coupon must be included to create new account")))
          (t
           (let ((url (parse-coupon coupon)))
             (handler-case
                 (verify-coupon client coupon nil url :http-proxy proxy)
               (error (c)
                 (json-error "Coupon didn't verify: ~a" c))))))
    (newuser client :passphrase passphrase :privkey (or privkey keysize))
    (let ((session (login-new-session client passphrase)))
      ;; Not calling maybe-start-server here. Maybe I should
      (handler-case
          (addserver client (or coupon url) :name name :couponok t
                     :http-proxy proxy)
        (error (c)
          (logout client)
          (json-error "Failed to add server: ~a" c)))
      (when fetch-privkey?
        (setf (privkey-cached-p client) t))
      session)))

(defun json-getprivkey (client args)
  (with-json-args (passphrase) args
    (login client passphrase)
    (encode-rsa-private-key (privkey client) passphrase)))

(defun json-login (client args)
  (with-json-args (passphrase) args
    (let ((session (login-new-session client passphrase)))
      (%setserver-json client)
      session)))

(defun %setserver-json (client)
  (let ((serverid (user-preference client "serverid")))
    (ignore-errors (setserver client serverid nil))
    (or (serverid client)
        (dolist (server (getservers client))
          (ignore-errors
            (setserver client (server-info-id server))
            (setf (user-preference client "serverid") serverid)
            (return (server-info-id server)))))))

(defun %login-json (client args)
  (with-json-args (session) args
    (login-with-sessionid client session)
    (%setserver-json client)))

(defun json-logout (client args)
  (%login-json client args)
  (logout client))

(defun json-current-user (client args)
  (%login-json client args)
  (id client))

(defun json-user-pubkey (client args)
  (%login-json client args)
  (pubkey client))

(defun json-getserver (client args)
  (%login-json client args)
  (with-json-args (serverid) args
    (unless serverid
      (setf serverid (serverid client))
      (unless serverid
        (json-error "There is no current server")))
    (let ((server (or (getserver client serverid)
                      (json-error "There is no server with id: ~a" serverid))))
      (%json-server-alist server))))

(defun %json-server-alist (server)
  `(("@type" . "server")
    ("id" . ,(server-info-id server))
    ("name" . ,(server-info-name server))
    ("url" . ,(server-info-url server))
    ,@(let ((host (server-info-proxy-host server)))
           (when host
             `(("proxy"
                .
                ,(format nil "~s:~d"
                         host (server-info-proxy-port server))))))))

(defun json-getservers (client args)
  (%login-json client args)
  (loop for server in (getservers client)
     collect (%json-server-alist server)))

(defun json-addserver (client args)
  (%login-json client args)
  (with-json-args (coupon name proxy) args
    (addserver client coupon :name name :http-proxy (parse-proxy proxy))
    (serverid client)))

(defun json-setserver (client args)
  (%login-json client args)
  (with-json-args (serverid) args
    (setserver client serverid)))

(defun json-currentserver (client args)
  (%login-json client args)
  (serverid client))

(defun json-privkey-cached? (client args)
  (%login-json client args)
  (with-json-args (serverid) args
    (privkey-cached-p client serverid)))

(defun json-cache-privkey (client args)
  (%login-json client args)
  (with-json-args (session uncache?) args
    (cache-privkey client session uncache?)))
  
(defun json-getcontact (client args)
  (%login-json client args)
  (with-json-args (id) args
    (let ((contact (getcontact client id)))
      (unless contact
        (json-error "There is no contact with id: ~a" id))
      (%json-contact-alist contact))))

(defun %json-optional (name value)
  (when value
    `((,name . ,value))))

(defun %json-contact-alist (contact)
  `(("@type" . "contact")
    ("id" . ,(contact-id contact))
    ("name" . ,(contact-name contact))
    ,@(%json-optional "nick" (contact-nickname contact))
    ,@(%json-optional "note" (contact-note contact))))

(defun json-getcontacts (client args)
  (%login-json client args)
  (loop for contact in (getcontacts client)
     collect (%json-contact-alist contact)))

(defun json-addcontact (client args)
  (%login-json client args)
  (with-json-args (id nickname note) args
    (addcontact client id nickname note)
    nil))

(defun json-deletecontact (client args)
  (%login-json client args)
  (with-json-args (id) args
    (deletecontact client id)))

(defun json-sync-contacts (client args)
  (%login-json client args)
  (sync-contacts client)
  nil)

(defun json-getasset (client args)
  (%login-json client args)
  (with-json-args (assetid force-server?) args
    (let ((asset (getasset client assetid force-server?)))
      (unless asset
        (json-error "There is no asset with id: ~a" assetid))
      (%json-asset-alist asset))))

(defun %json-asset-alist (asset)
  `(("@type" . "asset")
    ("id" . ,(asset-id asset))
    ("assetid" . ,(asset-assetid asset))
    ("scale" . ,(parse-integer (asset-scale asset)))
    ("precision" . ,(parse-integer (asset-precision asset)))
    ("name" . ,(asset-name asset))
    ,@(%json-optional "issuer" (asset-issuer asset))
    ,@(%json-optional "percent" (asset-percent asset))))

(defun json-getassets (client args)
  (%login-json client args)
  (loop for asset in (getassets client)
     collect (%json-asset-alist asset)))

(defun json-addasset (client args)
  (%login-json client args)
  (with-json-args (scale precision assetname percent) args
    (unless (and (typep scale '(integer 0))
                 (typep precision '(integer 0)))
      (json-error "scale and precision must be positive integers"))
    (unless (and (stringp assetname)
                 (not (blankp assetname)))
      (error "assetname must be a non-blank string"))
    (unless (or (null percent) (stringp percent))
      (error "percent must be null or a string"))
    (asset-assetid (addasset client
                             (as-string scale)
                             (as-string precision)
                             assetname percent))))

(defun json-getfees (client args)
  (%login-json client args)
  (with-json-args (reload?) args
    (multiple-value-bind (tranfee regfee other-fees)
        (getfees client reload?)
      (loop for fee in (list* tranfee regfee other-fees)
         collect (%json-fee-alist fee)))))

(defun %json-fee-alist (fee)
  `(("@type" . "fee")
    ("type" . ,(fee-type fee))
    ("assetid" . ,(fee-assetid fee))
    ("assetname" . ,(fee-assetname fee))
    ("amount" . ,(fee-amount fee))
    ("formatted-amount" . ,(fee-formatted-amount fee))))

(defun json-getbalance (client args)
  (%login-json client args)
  (with-json-args (assetid acct) args
    (unless acct (setf acct $MAIN))
    (let ((bal (getbalance client acct assetid)))
      (%json-balance-alist bal))))

(defun %json-balance-alist (bal)
  `(("@type" . "balance")
    ("acct" . ,(balance-acct bal))
    ("assetid" . ,(balance-assetid bal))
    ("assetname" . ,(balance-assetname bal))
    ("amount" . ,(balance-amount bal))
    ("time" . ,(balance-time bal))
    ("formatted-amount" . ,(balance-formatted-amount bal))))

(defun json-getbalances (client args)
  (%login-json client args)
  (with-json-args (assetid acct) args
    (let ((bals (getbalance client (or acct t) assetid)))
      (unless (listp bals)
        (setf bals `((,acct ,bals))))
      (loop for acct.bals in bals
         nconc (loop for bal in (cdr acct.bals)
                  collect (%json-balance-alist bal))))))

(defun json-getfraction (client args)
  (%login-json client args)
  (with-json-args (assetid) args
    (unless (stringp assetid)
      (json-error "assetid must be a string"))
    (let ((fraction (getfraction client assetid)))
      (%json-fraction-alist fraction))))

(defun %json-fraction-alist (fraction)
  `(("@type" . "fraction")
    ("assetid" . ,(fraction-assetid fraction))
    ("assetname" . ,(fraction-assetname fraction))
    ("amount" . ,(fraction-amount fraction))
    ("sclae" . ,(fraction-scale fraction))))

(defun json-getfractions (client args)
  (%login-json client args)
  (loop for fraction in (getfraction client)
     collect (%json-fraction-alist fraction)))

(defun json-getstoragefee (client args)
  (%login-json client args)
  (with-json-args (assetid) args
    (unless (stringp assetid)
      (json-error "assetid must be a string"))
    (let ((fee (getstoragefee client assetid)))
      (%json-storagefee-alist fee))))

(defun %json-storagefee-alist (fee)
  `(("@type" . "storagefee")
    ("assetid" . ,(balance-assetid fee))
    ("assetname" . ,(balance-assetname fee))
    ("amount" . ,(balance-amount fee))
    ("time" . ,(balance-time fee))
    ("formatted-amount". ,(balance-formatted-amount fee))
    ("fraction" . ,(balance+fraction-fraction fee))))

(defun json-getstoragefees (client args)
  (%login-json client args)
  (loop for fee in (getstoragefee client)
     collect (%json-storagefee-alist fee)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Copyright 2012 Bill St. Clair
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