(import
  scheme
  (distill plan)
  (distill package)
  (distill filepath)
  (distill buildenv)
  (distill base)
  (distill image)
  (distill linux)
  (distill service)
  (chicken file)
  (chicken process-context)
  (only (srfi 1) filter)
  (only (srfi 13) substring/shared))

;; this script builds every package in pkg/*.scm
;; (if it is out-of-date)

(define (package-handle name)
  (eval `(import (pkg ,name)))
  (eval name))

(define (trim-suffix str suff)
  (let* ((strlen (string-length str))
         (suflen (string-length suff))
         (diff   (- strlen suflen)))
    (and (>= diff 0)
         (let ((end (substring/shared str diff strlen)))
           (and (string=? end suff)
                (substring/shared str 0 diff))))))

(define package-names
  (find-files
    "./pkg"
    action: (lambda (f lst)
              (let ((suf (trim-suffix f ".scm")))
                (if suf (cons (string->symbol (basename suf)) lst) lst)))
    seed: '()))

(define (builtin-for conf)
  (letrec-syntax ((builtin* (syntax-rules ()
                              ((_) '())
                              ((_ (name expr) rest* ...)
                               (let ((tail (builtin* rest* ...)))
                                 (if expr
                                   (cons (cons (quote name) name) tail)
                                   tail)))
                              ((_ name rest* ...)
                               (cons (cons (quote name) name) (builtin* rest* ...))))))
    (builtin*
      musl
      libssp-nonshared
      libgmp
      libmpfr
      libmpc
      libisl
      zlib
      bzip2
      gawk
      byacc
      reflex
      make
      skalibs
      busybox-core
      busybox-full
      execline-tools
      xz-utils
      lz4
      zstd
      squashfs-tools
      libarchive
      libressl
      s6
      s6-rc
      linux-headers
      (perl              (eq? (conf 'arch) *this-machine*))
      (linux-virt-x86_64 (eq? (conf 'arch) 'x86_64)))))

(let* ((config  (let ((args (command-line-arguments)))
                  (if (null? args)
                    (build-config)
                    (default-config (string->symbol (car args))))))
       (build!  (config->builder config))
       (loaded  (map (lambda (name)
                       (cons name (package-handle name)))
                     package-names))
       (builtin (builtin-for config))
       (all     (append loaded builtin))
       (outputs (apply build! (map cdr all))))
  (for-each
    (lambda (name out)
      (display name)
      (display " ")
      (display (short-hash (artifact-hash out)))
      (newline))
    (map car all)
    outputs))
