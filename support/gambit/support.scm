(define (blodwen-read-args desc)
  (case (vector-ref desc 0)
    ((0) '())
    ((1) (cons (vector-ref desc 2)
               (blodwen-read-args (vector-ref desc 3))))))

(define (b+ x y bits) (remainder (+ x y) (arithmetic-shift 1 bits)))
(define (b- x y bits) (remainder (- x y) (arithmetic-shift 1 bits)))
(define (b* x y bits) (remainder (* x y) (arithmetic-shift 1 bits)))
(define (b/ x y bits) (remainder (exact-floor (/ x y)) (arithmetic-shift 1 bits)))

(define blodwen-and bitwise-and)
(define blodwen-or bitwise-ior)
(define blodwen-xor bitwise-xor)
(define blodwen-shl arithmetic-shift)
(define (blodwen-shr x y) (arithmetic-shift x (- y)))

(define exact-floor ##flonum->fixnum) ; XXX

(define (cast-string-double x)
  (define (cast-num x)
    (if (number? x) x 0))
  (define (destroy-prefix x)
    (if (or (equal? x "") (char=? (string-ref x 0) #\#)) "" x))
  (cast-num (string->number (destroy-prefix x))))

(define (cast-string-int x)
  (exact-floor (cast-string-double x)))

(define (string-cons x y)
  (string-append (string x) y))

(define (string-reverse x)
  (list->string (reverse! (string->list x))))

(define (string-substr off len s)
  (let* ((start (max 0 off))
         (end (min (+ start (max 0 len))
                   (string-length s))))
    (substring s start end)))

(define (get-tag x)
  (vector-ref x 0))

;; These two are only used in this file
(define (either-left x) (vector 0 x))
(define (either-right x) (vector 1 x))

(define (blodwen-error-quit msg)
  (display msg)
  (newline)
  (exit 1))

;; Buffers

(define blodwen-new-buffer make-bytevector)
(define blodwen-buffer-size bytevector-length)

(define blodwen-buffer-setbyte u8vector-set!)
(define blodwen-buffer-getbyte u8vector-ref)

(define blodwen-buffer-setint s32vector-set!)
(define blodwen-buffer-getint s32vector-ref)

(define blodwen-buffer-setdouble f64vector-set!)
(define blodwen-buffer-getdouble f64vector-ref)

(define (blodwen-stringbytelen str)
  (bytevector-length (string->utf8 str)))

(define (blodwen-buffer-setstring buf loc val)
  (let* ((strvec (string->utf8 val))
         (len (bytevector-length strvec)))
    (bytevector-copy! strvec 0 buf loc len)))

(define (blodwen-buffer-getstring buf loc len)
  (let ((newvec (make-bytevector len)))
    (bytevector-copy! buf loc newvec 0 len)
    (utf8->string newvec)))

(define (blodwen-buffer-copydata buf start len dest loc)
  (bytevector-copy! buf start dest loc len))

(define (blodwen-readbuffer-bytes h buf loc max)
  (with-exception-catcher
    (lambda (e) -1)
    (lambda () (read-subu8vector buf loc (+ loc max) h))))

(define (blodwen-readbuffer h)
  (with-exception-catcher
    (lambda (e) #u8())
    (lambda () (list->u8vector (read-all h read-u8)))))

(define (blodwen-writebuffer h buf loc max)
  (with-exception-catcher
    (lambda (e) -1)
    (lambda () (write-subu8vector buf loc (+ loc max) h) max)))

;; Files

;; If the file operation raises an error, catch it and return an appropriate
;; error code
(define (blodwen-file-op op)
  ;; All the file operations are implemented as primitives which return
  ;; Either Int x, where the Int is an error code:
  (define (blodwen-error-code x)
    (define magic ;; For errno extraction
      (fx- 0 (fxnot (- (fxarithmetic-shift 1 29) 1)) (fxarithmetic-shift 320 16)))
    (either-left
      ;; TODO Equivalent of i/o-read-error? and i/o-write-error?
      ;; TODO Uncomment on the next release (> 4.9.3) of Gambit
      (cond ((no-such-file-or-directory-exception? x) 3)
            ; ((permission-denied-exception? x) 4)
            ; ((file-exists-exception? x) 5)
            (else (fx+ (os-exception-code x) magic 256)))))
  (with-exception-catcher
    blodwen-error-code
    (lambda () (either-right (op)))))

#|
(define (blodwen-get-n n p)
  (if (input-port? p) (read-string n p) ""))
|#

(define (blodwen-putstring p s)
  (if (output-port? p) (write-string s p))
  0)

(define (blodwen-open file mode bin)
  (define settings
    (if (fx= bin 1)
        `(path: ,file buffering: line)
        `(path: ,file buffering: line char-encoding: UTF-8)))
  (cond
    ((string=? mode "r") (open-input-file settings))
    ((string=? mode "w") (open-output-file settings))
    ((string=? mode "wx") (open-output-file (append settings '(create: #t))))
    ((string=? mode "a") (open-output-file (append settings '(append: #t))))
    ((string=? mode "r+") (open-file settings))
    ((string=? mode "w+") (open-file (append settings '(create: maybe truncate: #t))))
    ((string=? mode "w+x") (open-file (append settings '(create: #t truncate: #t))))
    ((string=? mode "a+") (open-file (append settings '(create: maybe append: #t))))
    (else (raise 'i/o-error)))) ; XXX

(define (blodwen-close-port p)
  (if (port? p) (close-port p)))

(define (blodwen-get-line p)
  (if (input-port? p)
      (let ((str (read-line p #\newline #t)))
        (if (eof-object? str) "" str))
      ""))

(define (blodwen-get-char p)
  (if (input-port? p)
      (let ((chr (read-char p)))
        (if (eof-object? chr) #\nul chr))
      #\nul))

(define (blodwen-file-modified-time p) ; XXX
  (exact-floor (time->seconds (file-last-modification-time (##port-name p)))))

#|
(define (blodwen-file-size p) ; XXX
  (file-size (##port-name p)))
|#

(define (blodwen-eof p)
  (if (eof-object? (peek-char p)) 1 0))

;; Directories

(define blodwen-current-directory current-directory)

(define (blodwen-change-directory dir)
  (with-exception-catcher
    (lambda (e) 0)
    (lambda () (current-directory dir) 1)))

(define (blodwen-create-directory dir)
  (blodwen-file-op (lambda () (create-directory dir) 0)))

(define (blodwen-open-directory dir)
  (blodwen-file-op (lambda () (open-directory dir))))

(define blodwen-close-directory close-input-port)

(define (blodwen-next-dir-entry dir)
  (let ((e (read dir)))
    (if (eof-object? e)
        (either-left 255)
        (either-right e))))

;; Threads

(define (blodwen-thread p)
  (thread-start! (make-thread (lambda () (p #(0))))))

(define (blodwen-get-thread-data)
  (let ((data (thread-specific (current-thread))))
    (if (eq? data #!void) #f data)))

(define (blodwen-set-thread-data a)
  (thread-specific-set! (current-thread) a))

(define blodwen-mutex make-mutex)
(define blodwen-lock mutex-lock!)
(define blodwen-unlock mutex-unlock!)
(define blodwen-thisthread current-thread)

(define blodwen-condition make-condition-variable)
(define blodwen-condition-signal condition-variable-signal!)
(define blodwen-condition-broadcast condition-variable-broadcast!)
(define (blodwen-condition-wait c m)
  (mutex-unlock! m c)
  (mutex-lock! m))
(define (blodwen-condition-wait-timeout c m t) ; XXX
  (mutex-unlock! m c t)
  (mutex-lock! m))

(define blodwen-sleep thread-sleep!)
(define (blodwen-usleep s) (thread-sleep! (/ s 1e6)))

(define (blodwen-time)
  (exact-floor (time->seconds (current-time))))

(define (blodwen-args)
  (define (blodwen-build-args args)
    (if (null? args)
        #(0) ; Prelude.List
        (vector 1 (car args) (blodwen-build-args (cdr args)))))
  (blodwen-build-args (cdr (command-line))))

(define (blodwen-hasenv var)
  (if (getenv var #f) 1 0))

(define (blodwen-system cmd)
  (fxarithmetic-shift-right (shell-command cmd) 8))
