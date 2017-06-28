#lang rosette/safe

;; stolen from previous interpreter

(define (build-list n proc)
  (build-list-helper 0 n proc))

(define (build-list-helper i n proc)
  (if (< i n)
      (cons (proc i) (build-list-helper (+ i 1) n proc))
      '()))

(define (build-vector n proc)
  (list->vector (build-list n proc)))

(define (clone-vector vec)
  (build-vector (vector-length vec) (lambda (i) (vector-ref vec i))))

(define (symbolic-integer)
  (define-symbolic* i integer?)
  i)

(define (symbolic-integer)
  (define-symbolic* i integer?)
  i)

(define (symbolic-bv n)
  (define-symbolic* b (bitvector n))
  i)

;; For now, let's assume that the processor state is a vector of 31 64-bit bitvectors
(define (symbolic-registers)
  (build-vector 31 (lambda (i) (symbolic-bv 64))))

;; We might not want to always make all of the registers symbolic, but we can worry about
;; that more later.

;; Since we don't have any notion of memory, a program can just be a list of instructions,
;; encoded as bitvectors. The table in TAG:aarch64/instrs/integer/arithmetic/add-sub/shiftedreg:diagram
;; explains how to decode the fields.

;; The emulator can use a typical fetch / decode / execute loop. Fetch is easy (we just get
;; the next bitvector in the list of instructions) and then based on the fields we would
;; choose the right decode and execute implementations to run. Those implementations
;; would presumably call into other code translated from the ASL description.

;; We should do something eventually with the processor state that holds things like
;; the flags. That will probably be a struct with a bunch of really short bitvectors in it.

(struct aarch64state (N Z C V regs) #:transparent)

(define (step state prog)
  'unimplemented)

;; Take a stab at filling this out. It will probably make sense to pull out things like
;; decode and execute into separate functions. You can try to approximately follow the
;; organization of the ASL.

;; This is a pretty big project already with a lot going on, so nothing we do here is
;; going to be set in stone. The important thing is to get a little more familiar with
;; ASL and Rosette.
