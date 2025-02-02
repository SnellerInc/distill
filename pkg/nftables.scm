(import
 scheme
 (distill plan)
 (distill package)
 (distill base)
 (pkg libreadline)
 (pkg ncurses)
 (pkg jansson))

(define nftables
  (cmmi-package
   "nftables" "0.9.9"
   "http://netfilter.org/projects/nftables/files/$name-$version.tar.bz2"
   "xZDlbMRtT82r3nwMOtjtQDza-aqvfPd8vvDN3zDzmP8="
   env:  '((LIBMNL_LIBS . -lmnl)
           (LIBMNL_CFLAGS . -lmnl)
           (LIBNFTNL_LIBS . -lnftnl)
           (LIBNFTNL_CFLAGS . -lnftnl))
   libs: (list ncurses jansson libgmp libmnl libnftnl linux-headers)
   tools: (list reflex byacc (interned-symlink "/usr/bin/byacc" "/usr/bin/yacc"))
   extra-configure: '(--disable-man-doc --without-cli --with-json)))
