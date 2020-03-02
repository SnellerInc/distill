(define-library (distill package)
  (import
    (scheme base)
    (scheme write)
    (srfi 26) ;; cut
    (srfi 69) ;; make-hash-table, etc
    (distill memo)
    (distill table)
    (distill eprint)
    (distill execline)
    (distill contract)
    (distill kvector)
    (distill filepath)
    (distill plan))
  (cond-expand
    (chicken (import
               (chicken type)
               (chicken keyword)
               (only (chicken string) conc)
               (only (chicken port)
                     with-output-to-string
                     call-with-output-string)
               (only (chicken base) flatten))))
  (export
    *this-machine*
    patch*
    script-apply-patches
    strip-binaries-script
    build-config
    default-config
    config->builder
    package->stages
    
    package?
    make-package
    update-package
    package-label
    package-tools
    package-inputs
    package-build
    package-prebuilt

    make-recipe
    recipe?
    recipe-env
    recipe-script

    $arch
    $sysroot
    $triple
    $make-overrides
    $cc-env
    build-triple
    $CC
    $AR
    $LD
    $NM
    $CFLAGS
    $LDFLAGS
    $ARFLAGS
    $RANLIB
    $READELF
    $gnu-build
    +cross
    gnu-recipe
    $ska-build
    ska-recipe
    cc-env/build
    cc-env/for-build
    cc-env/for-kbuild
    spaced
    splat
    k=v*
    kvargs
    kvexport)
  (include "package.scm"))
