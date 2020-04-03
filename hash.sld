(define-library (distill hash)
  (export
    new-hasher
    hash-write!
    hash-finalize
    hash-of
    hash-file

    with-output-to-hash
    hasher->output-port)
  (import
    scheme
    (srfi 4)
    (srfi 26)
    (srfi 39))
  (cond-expand
    (chicken
      (import
        (only (chicken fixnum) fx=)
        (only (chicken io) read-string!)
        (only (chicken port) make-output-port)
        (only (chicken base) include error)
	(only (chicken blob) blob->string string->blob)
	(chicken foreign)
	(chicken type))))
  (include "hash.scm"))
