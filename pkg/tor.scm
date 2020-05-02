(import
  scheme
  (distill base)
  (distill package)

  (pkg libevent)
  (pkg libcap))

(define tor
  (cmmi-package
   "tor" "0.4.2.7"
   "https://dist.torproject.org/$name-$version.tar.gz"
   "JftNScwww-HwiTXndd_Ir_CDlvrENg_ryiG9SIbzSEw="
   env: '((ZSTD_CFLAGS . "")
	  (ZSTD_LIBS . "-lzstd")
	  ;; the configure script makes some assumptions
	  ;; when cross-compiling; let's make them explicit:
	  (tor_cv_dbl0_is_zero . yes)
	  (tor_cv_null_is_zero . yes)
	  (tor_cv_malloc_zero_works . yes) ; malloc(0)!=NULL
	  (tor_cv_twos_complement . yes))
   libs: (list linux-headers libevent libressl zlib zstd libcap)
   extra-configure: '(--enable-all-bugs-are-fatal
		      --enable-zstd
		      --disable-manpage
		      --disable-html-manual
		      --disable-asciidoc
		      --disable-systemd
		      --disable-rust)
   ;; config comes from service definition
   cleanup: '((if ((rm -rf /out/etc))))))
