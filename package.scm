(: *this-machine* symbol)
(define *this-machine*
  (cond-expand
   (x86-64 'x86_64)
   (arm64  'aarch64)
   ;; TODO: additional verification that this is armv7-a
   (arm    'armv7)
   ((and ppc64 little-endian) 'ppc64le)
   ((and ppc64 big-endian) 'ppc64)))

(define <meta-package> (list 'meta-package))

;; make-metapackage is an alternative for
;; make-package that simply returns a list
;; of other packages and/or artifacts
(define (make-meta-package proc)
  (vector <meta-package> proc))

(: meta-package? (* -> boolean))
(define (meta-package? arg)
  (and (vector? arg)
       (= (vector-length arg) 2)
       (eq? (vector-ref arg 0) <meta-package>)))

(define-memoized (meta-expand mp conf)
  ((vector-ref mp 1) conf))

(define inputs? (list-of (disjoin procedure? meta-package? artifact?)))

(define-kvector-type
  <package>
  make-package
  package?
  (package-label    label:   #f  string?)
  (package-src      src:     '() (disjoin artifact? (list-of artifact?)))
  (package-tools    tools:   '() inputs?)
  (package-inputs   inputs:  '() inputs?)
  (package-prebuilt prebuilt: #f (perhaps artifact?))
  (package-patches  patches: '() (list-of artifact?))
  (package-build    build:   #f  list?)
  (package-dir      dir:     "/" string?)
  (package-env      env:     '() (list-of (disjoin pair? kvector?)))
  (package-raw-output raw-output: #f (perhaps string?)))

;; vargs takes a list of arguments,
;; some of which are functions,
;; and delays their expansion into
;; a list of concrete arguments once a config is supplied
(define (vargs lst)
  (lambda (conf)
    (let ((sublist (lambda (lst)
		     (foldl
		      (lambda (str item)
			(string-append
			 str
			 (cond
			  ((string? item) item)
			  ((symbol? item) (##sys#symbol->string item))
			  ((procedure? item) (spaced (item conf)))
			  ((number? item) (number->string item))
			  (else (error "bad item in vargs" item)))))
		      ""
		      lst))))
      (reverse
       (foldl
	(lambda (lst item)
	  (cond
	   ((procedure? item)
	    ;; if the config variable is a kvector,
	    ;; splat it into the list
	    (let ((res (item conf)))
	      (cond
	       ((kvector? res)
		(kvector-foldl
		 res
		 (lambda (k v lst)
		   (if v
		       (cons (string-append (##sys#symbol->string k) "=" (spaced v)) lst)
		       lst))
		 lst))
	       ((list? res)
		(let loop ((in res) (out lst))
		  (if (null? in) out (loop (cdr in) (cons (car in) out)))))
	       (else (cons res lst)))))
	   ((list? item)
	    (cons (sublist item) lst))
	   (else (cons item lst))))
	'()
	lst)))))

;; cdelay produces a delayed evaluation
;; of 'proc' with a <config> as its only argument
;;
;; useful for wrapping script generation
(define (cdelay proc)
  (lambda (conf)
    (proc (lambda (v) (if (procedure? v) (v conf) v)))))

;; csubst is similar to cdelay
(define (csubst proc)
  (lambda (conf)
    (proc (lambda (fn) (fn conf)))))

(define (cmd* first . rest)
  (csubst
   (lambda (subst)
     (let ((cmdline (lambda (arglst)
		      (cond
		       ((pair? arglst)
			;; accept (cmd ...) forms and also
			;; ((cmd ...) ...) forms
			(if (pair? (car arglst))
			    (map (lambda (cmd) (subst (vargs cmd))) arglst)
			    (list (subst (vargs arglst)))))
		       ((procedure? arglst)
			(subst arglst))
		       (else (error "unexpected argument to cmd*" arglst))))))
       (let loop ((first first)
		  (rest  rest))
	 (if (null? rest)
	     ;; allow the terminal expression to be
	     ;; a list-of-lists, which means it is
	     ;; another sequence of programs (perhaps another (cmd* ...) expression)
	     (let ((tail (cmdline first)))
	       (if (and (pair? tail) (pair? (car tail)))
		   tail
		   (list tail)))
	     (cons `(if ,(cmdline first)) (loop (car rest) (cdr rest)))))))))

(define (url-translate urlfmt name version)
  (string-translate* urlfmt `(("$name" . ,name)
			      ("$version" . ,version))))

;; template for C/C++ packages
;;
;; the cc-package template picks suitable defaults
;; for the package source, inputs (libc), tools (toolchain)
;; and build directory; the additional keyword arguments
;; can be used to augment that package template with
;; more libraries and tools
;;
;; the 'build:' argument is mandatory; cc-package
;; does not provide a default build script
(define (cc-package
	 name version urlfmt hash
	 #!key
	 (dir #f) ;; directory override
	 (build #f)
	 (prebuilt #f) ;; prebuilt function
	 (no-libc #f)	 ;; do not bring in a libc implicitly
	 (use-native-cc #f)
	 (raw-output #f)
	 (patches '()) ;; patches to apply
	 (env '())	 ;; extra environment
	 (libs '())	 ;; extra libraries beyond libc
	 (tools '())	 ;; extra tools beyond a C toolchain
	 (extra-src '()))
  (let* ((url (url-translate urlfmt name version))
	 (src (remote-archive url hash)))
    (lambda (conf)
      (let* ((ll  (lambda (l) (if (procedure? l) (l conf) l)))
	     (ctc ($cc-toolchain conf)))
	(make-package
	 raw-output: raw-output
	 prebuilt: (ll prebuilt)
	 patches: patches
	 label:   (conc name "-" version "-" ($arch conf))
	 src:     (cons src (append patches extra-src))
	 env:     (ll env)
	 dir:     (or dir (conc name "-" version))
	 tools:   (append (cc-toolchain-tools ctc)
			  (ll tools)
			  (if use-native-cc
			      (let ((ntc ($native-toolchain (build-config))))
				(append (cc-toolchain-tools ntc) (cc-toolchain-libc ntc)))
			      '()))
	 inputs:  (append (if no-libc '() (cc-toolchain-libc ctc)) (ll libs))
	 build:   (if build (ll build) (error "cc-package needs build: argument")))))))

;; template for 'configure; make; make install;' or 'c;m;mi'
;; that has sane defaults for environment, tools, libraries
;; (see cc-package) and a reasonable default for the build script.
;;
(define (cmmi-package
	 name version urlfmt hash
	 #!key
	 (dir #f)    ;; directory override
	 (prebuilt #f) ;; prebuilt function
	 (patches '()) ;; patches to apply
	 (env '())	 ;; extra environment

	 ;; override-configure, if not #f, takes
	 ;; precedence over the default configure options;
	 ;; otherwise (append default extra-configure) is used
	 (extra-configure '())
	 (override-configure #f)

	 (override-make #f)
	 (override-install #f)
	 (out-of-tree #f)

	 (libs '())	 ;; extra libraries beyond libc
	 (tools '())	 ;; extra tools beyond a C toolchain
	 (extra-src '()) ;; extra source
	 (prepare '())   ;; a place to put sed chicanery, etc.
	 (cleanup '())   ;; a place to put extra install tweaking
	 (native-cc #f) ;; should be one of the cc-env/for-xxx functions if not #f
	 (extra-cflags '()))
  (let* ((default-configure (vargs
			     `(--disable-shared
			       --enable-static
			       --disable-nls
			       --prefix=/usr
			       --sysconfdir=/etc
			       ;; delay the evaluation of the build machine
			       ;; in case build-config is re-parameterized
			       --build ,(lambda (conf)
					  ($triple (build-config)))
			       --host ,$triple)))
	 (make-args (or override-make (vargs (list $make-overrides)))))
    (cc-package
     name version urlfmt hash
     dir: dir
     patches: patches
     prebuilt: prebuilt
     libs: libs
     tools: tools
     extra-src: extra-src
     use-native-cc: (if native-cc #t #f)
     env:     (cdelay
	       (lambda (ll)
		 (cons
		  (if (null? extra-cflags)
		      (ll $cc-env)
		      (kwith (ll $cc-env)
			     CFLAGS: (+= extra-cflags)
			     CXXFLAGS: (+= extra-cflags)))
		  (if native-cc
		      (cons (native-cc) (ll env))
		      (ll env)))))
     build:   (cdelay
	       (lambda (ll)
		 (append
		  (ll prepare)
		  (let ((args (or (ll override-configure)
				  (append (ll default-configure)
					  (ll extra-configure)))))
		    (if out-of-tree
			`((if ((mkdir -p distill-builddir)))
			  (cd distill-builddir)
			  (if ((../configure ,@args))))
			`((if ((./configure ,@args))))))
		  `((if ((make ,@(ll make-args))))
		    (if ((make ,@(or (ll override-install) '(DESTDIR=/out install)))))
		    (foreground ((rm -rf /out/usr/share/man /out/usr/share/info)))
		    (foreground ((find /out -name "*.la" -delete))))
		  (ll cleanup)
		  (ll (lambda (conf)
			(strip-binaries-script ($triple conf))))))))))

(: update-package (vector #!rest * -> vector))
(define (update-package pkg . args)
  (apply make-package
	 (append
	  (kvector->list pkg)
	  args)))

(: <cc-env> vector)
(define <cc-env>
  (make-kvector-type
   AR:
   AS:
   CC:
   LD:
   NM:
   CXX:
   CBUILD:
   CHOST:
   CFLAGS:
   ARFLAGS:
   CXXFLAGS:
   LDFLAGS:
   RANLIB:
   STRIP:
   READELF:
   OBJCOPY:))

(define cc-env? (kvector-predicate <cc-env>))
(define make-cc-env (kvector-constructor <cc-env>))

(define-kvector-type
  <cc-toolchain>
  make-cc-toolchain
  cc-toolchain?
  (cc-toolchain-tools tools: '() inputs?)
  (cc-toolchain-libc  libc:  '() inputs?)
  (cc-toolchain-env   env:   #f  cc-env?))

(define-kvector-type
  <config>
  make-config
  config?
  ($arch         arch:         #f symbol?)
  ($triple       triple:       #f symbol?)
  ($cc-toolchain cc-toolchain: #f cc-toolchain?)
  ($native-toolchain native-cc-toolchain: #f cc-toolchain?))

(define $cc-env (o cc-toolchain-env $cc-toolchain))

(define (build-getter kw)
  (let ((get (kvector-getter <cc-env> kw)))
    (lambda (_)
      (get (cc-toolchain-env ($native-toolchain (build-config)))))))

(define $build-CC (build-getter CC:))
(define $build-LD (build-getter LD:))
(define $build-CFLAGS (build-getter CFLAGS:))

;; sort of a hack to keep a circular dependency
;; between base.scm and package.scm from creeping in:
;; have package.scm declare the 'build-config'
;; parameter, but have 'base.scm' set it as soon
;; as it declares default-config
(: build-triple (-> symbol))
(define (build-triple) ($triple (build-config)))
(define ($build-triple conf) (build-triple))
(define ($cross-compile conf) (conc ($triple conf) "-"))

(define (triple->sysroot trip)
  (string-append "/sysroot/" (symbol->string trip)))

(define ($sysroot conf)
  (triple->sysroot ($triple conf)))

(define (triple->arch trip)
  (string->symbol (car (string-split (symbol->string trip) "-"))))

(define (cenv v) (o (kvector-getter <cc-env> v) $cc-env))

(define $CC (cenv CC:))
(define $CXX (cenv CXX:))
(define $CFLAGS (cenv CFLAGS:))
(define $CXXFLAGS (cenv CXXFLAGS:))
(define $LD (cenv LD:))
(define $LDFLAGS (cenv LDFLAGS:))
(define $AR (cenv AR:))
(define $ARFLAGS (cenv ARFLAGS:))
(define $RANLIB (cenv RANLIB:))
(define $READELF (cenv READELF:))
(define $OBJCOPY (cenv OBJCOPY:))
(define $NM (cenv NM:))

;; $make-overrides is the subset of <config>
;; that is supplied as k=v arguments to invocations
;; of $MAKE (in order to override assignments in the Makefile)
(define $make-overrides
  (memoize-one-eq
   (o
    (subvector-constructor
     <cc-env>
     RANLIB: STRIP: NM: READELF: OBJCOPY: AR: ARFLAGS:)
    $cc-env)))

;; cc-env/build produces a C environment
;; by transforming the usual CC, LD, etc.
;; variables using (frob-kw key) for each keyword
(: cc-env/build ((keyword -> keyword) -> vector))
(define (cc-env/build frob-kw)
  (let ((folder (lambda (kw arg lst)
		  ;; ignore cc-env values that are #f
		  (if arg
		      (cons (frob-kw kw) (cons arg lst))
		      lst))))
    (list->kvector
     (kvector-foldl
      (cc-toolchain-env ($native-toolchain (build-config)))
      folder
      '()))))

;; cc-env/for-build is a C environment
;; with CC_FOR_BUILD, CFLAGS_FOR_BUILD, etc.
;; (this is typical for autotools-based configure scripts)
(define (cc-env/for-build)
  (cc-env/build (lambda (kw)
		  (string->keyword
		   (string-append
		    (keyword->string kw)
		    "_FOR_BUILD")))))

;; cc-env/for-kbuild is a C environment
;; with HOSTCC, HOSTCFLAGS, etc.
;; (this is typical for Kbuild-based build systems)
(define (cc-env/for-kbuild)
  (cc-env/build (lambda (kw)
		  (string->keyword
		   (string-append
		    "HOST"
		    (keyword->string kw))))))

(: spaced (* -> string))
(define (spaced lst)
  (let ((out (open-output-string)))
    (cond
     ((list? lst)
      (let loop ((lst lst))
	(or (null? lst)
	    (let ((head (car lst))
		  (rest (cdr lst)))
	      (if (list? head)
		  (loop head)
		  (display head out))
	      (unless (null? rest)
		      (display " " out))
	      (loop rest)))))
     (else (display lst out)))
    (let ((s (get-output-string out)))
      (close-output-port out)
      s)))

;; k=v takes a key and a value
;; and returns a string like "key=value"
;; where 'value' becomes space-separated
;; if it is a list
(: k=v (keyword * --> string))
(define (k=v k v)
  (unless (keyword? k)
	  (error "k=v expected a keyword but got" k))
  (string-append
   (##sys#symbol->string k)
   "="
   (spaced v)))

;; k=v* takes an arbitrary set of keyword: value forms
;; and converts them into a list of strings of the form keyword=value
(: k=v* (keyword * #!rest * --> (list-of string)))
(define (k=v* k v . rest)
  (let loop ((k k)
	     (v v)
	     (rest rest))
    (cons (k=v k v)
	  (if (null? rest)
	      '()
	      (let ((k  (car rest))
		    (vp (cdr rest)))
		(loop k (car vp) (cdr vp)))))))

;; kvargs takes a kvector
;; and produces a list of strings
;; where each string is formatted as "key=value"
;; for each key-value mapping in the kvector
(: kvargs (vector --> (list-of string)))
(define (kvargs kvec)
  (kvector-map kvec k=v))

;; splat takes a kvector and a list of keywords
;; and produces a list of key=value strings
;; for just those keywords in the kvector
(: splat (vector #!rest keyword --> (list-of string)))
(define (splat conf . keywords)
  (map
   (lambda (k)
     (k=v k (kref conf k)))
   keywords))

;; kvexport produces a list of non-terminal
;; execline expressions of the form
;;   (export <key> <value>)
;; for each element in the given kvector,
;; taking care to format values as a single
;; string, even if they are lists
(: kvexport (vector --> list))
(define (kvexport kvec)
  `((exportall ,(kvector-map
		 (lambda (k v)
		   (list (##sys#symbol->string k) (spaced v)))))))

;; build-config is the configuration
;; for artifacts produced for *this* machine (tools, etc)
;; (this is set to a reasonable value when base.scm is loaded)
(define build-config
  (make-parameter #f))

;; recursively apply 'proc' to items of lst
;; while the results are lists, and deduplicate
;; precisely-equivalent items along the way
;;
;; this is used to expand package#tools and package#inputs
;; so that meta-packages are recursively unpacked into a single
;; list of packages and artifacts
(define (expandl proc lst)
  (let loop ((in  lst)
	     (out '()))
    (if (null? in)
	out
	(let ((head (car in))
	      (rest (cdr in)))
	  (if (memq head rest)
	      (loop rest out)
	      (let ((h (proc head)))
		(loop (cdr in)
		      (cond
		       ((list? h) (loop h out))
		       ;; deduplicate 'eq?'-equivalent items
		       ((memq h out) out)
		       (else (cons h out))))))))))

;; config->builder takes a configuration (as an alist or conf-lambda)
;; and returns a function that builds the package
;; and yields its output artifact
(define (config->builder env)
  (let* ((host  (conform config? env))
	 (build (build-config))
	 (->plan/art (lambda (in)
		       (cond
			((artifact? in) in)
			((meta-package? in) (meta-expand in host))
			((procedure? in) (package->plan in build host))
			(else "bad item provided to plan builder" in))))
	 (->out (lambda (pln)
		  (cond
		   ((artifact? pln) pln)
		   ((procedure? pln) (let ((plan (package->plan pln build host)))
				       (if (artifact? plan) plan (plan-outputs plan))))
		   ;; TODO: meta-packages
		   (else #f)))))
    (lambda args
      (let ((plans (expandl ->plan/art args)))
	(unless (null? plans)
		(build-graph! plans))
	(map ->out args)))))


;; package->plan is the low-level package expansion code;
;; it recursively simplifies packges into plans, taking care
;; to only expand packges once for each (build, host) configuration tuple
(define package->plan
  (memoize-lambda
   (pkg-proc build host)
   (let ((pkg (pkg-proc host)))
     (or (package-prebuilt pkg)
	 (let* ((expander (lambda (conf)
			    (lambda (in)
			      (cond
			       ((artifact? in) in)
			       ((meta-package? in) (meta-expand in conf))
			       (else (package->plan in build conf))))))
		(->tool  (expander build))
		(->input (expander host))
		(tools   (package-tools pkg))
		(inputs  (package-inputs pkg)))
	   (make-plan
	    raw-output: (package-raw-output pkg)
	    name:   (package-label pkg)
	    inputs: (list
		     (cons "/" (cons*
				(package-buildfile pkg)
				(expandl ->tool (flatten (package-src pkg) tools))))
		     ;; build headers+libraries live here
		     (cons ($sysroot host) (expandl ->input inputs)))))))))

(: package-buildfile (vector -> vector))
(define (package-buildfile r)
  (interned
   "/build" #o744
   (lambda ()
     (write-exexpr
      (let ((dir (package-dir r))
	    (patches (or (package-patches r) '()))
	    (exports (package-env r)))
	(unless dir "error: no dir specified" r)
	(cons
	 `(cd ,dir)
	 (append
	  (script-apply-patches patches)
	  (exports->script exports)
	  (package-build r))))))))

;; generator for an execline sequence that strips binaries
(define (strip-binaries-script triple)
  `((forbacktickx file ((find /out -type f -perm -o+x)))
    (importas "-i" -u file file)
    (backtick prefix ((head -c4 $file)))
    (importas "-i" -u prefix prefix)
    ;; the execline printing code knows
    ;; how to escape a raw byte sequence
    ;; (elf binaries begin with (0x7f)ELF)
    (if ((test $prefix "=" #u8(127 69 76 70))))
    (if ((echo "strip" $file)))
    (,(conc triple "-strip") $file)))

(define ($strip-cmd conf) (strip-binaries-script ($triple conf)))

;; patch* creates a series of patch artifacts
;; from a collection of verbatim strings
(define (patch* . patches)
  (if (null? patches)
      '()
      (let loop ((n 0)
		 (head (car patches))
		 (rest (cdr patches)))
	(cons
	 (interned (conc "/src/patch-" n ".patch") #o644 head)
	 (if (null? rest) '() (loop (+ n 1) (car rest) (cdr rest)))))))

;; script-apply-patches produces the execline expressions
;; for applying a series of patches from artifact files
(define (script-apply-patches lst)
  (map
   (lambda (pf)
     `(if ((patch -p1 "-i" ,(vector-ref (vector-ref pf 0) 1)))))
   lst))

(define (exports->script lst)
  (let loop ((in  lst)
	     (exp '()))
    (if (null? in)
	(if (null? exp) '() `((exportall ,(reverse exp))))
	(let ((h (car in)))
	  (cond
	   ((pair? h)
	    (loop (cdr in) (cons (list (car h) (spaced (cdr h))) exp)))
	   ((kvector? h)
	    (loop (cdr in) (kvector-foldl
			    (car in)
			    (lambda (k v lst)
			      (if v (cons (list (##sys#symbol->string k) (spaced v)) lst) lst))
			    exp)))
	   (else (error "bad env element" (car in))))))))



