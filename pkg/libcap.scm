(import
  scheme
  (distill execline)
  (distill package)
  (distill base))

(define libcap
  (let* ((config+=    (lambda (getter extra)
			(lambda (conf)
			  (append (getter conf) extra))))
	 ($my-cflags        (config+= $CFLAGS '(-D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64)))
	 ($cflags-for-build (config+= $build-CFLAGS '("-I./include" "-I./include/uapi"))))
   (cc-package
    "libcap" "2.27"
    "https://kernel.org/pub/linux/libs/security/linux-privs/$name2/$name-$version.tar.xz"
    "2mB4u6ahspxKFsSPz21FWrHUC0YGDIwT7F_OGCw4RYg="
    use-native-cc: #t
    tools: (list perl linux-headers)
    libs:  (list linux-headers)
    build: (elif*
	    `(make -C libcap ,(el= 'CC= $CC) ,(el= 'CFLAGS= $my-cflags)
		   ,(el= 'BUILD_CC= $build-CC) ,(el= 'BUILD_CFLAGS= $cflags-for-build)
		   ,(el= 'AR= $AR) ,(el= 'RANLIB= $RANLIB)
		   libcap.a)
	    '(install -D -m "0644" libcap/include/sys/capability.h /out/usr/include/sys/capability.h)
	    '(install -D -m "0644" libcap/libcap.a /out/usr/lib/libcap.a)))))

