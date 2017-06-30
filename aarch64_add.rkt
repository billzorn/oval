#lang rosette/safe

;; use this to "throw an exception" instead of returning the symbol 'error
(define (emulator-undefined)
  (assert #f 'undefined))

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

(define (symbolic-bv n)
  (define-symbolic* b (bitvector n))
  b)

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

(struct aarch64state ([N #:mutable]
                      [Z #:mutable]
                      [C #:mutable]
                      [V #:mutable]
                      regs)
  #:transparent)


;; This is the global state of the emulator - the implementation can access it at will.
;; To work on multiple states, save the old one somewhere and put in a new one. The
;; reset function is a good way to get new states, but they aren't symbolic anywhere.

;; initially empty, call reset before doing anything
(define emulator-state (box '()))

(define (emulator-reset)
  (set-box! emulator-state
            (aarch64state (bv 0 1)
                          (bv 0 1)
                          (bv 0 1)
                          (bv 0 1)
                          (build-vector 31 (lambda (i) (bv 0 64))))))



(define (step state prog)
  ;; decode program instruction by bit disection
  (let* ([rd (extract 4 0 prog)]
         [rn (extract 9 5 prog)]
         [imm6 (extract 15 10 prog)]
         [rm (extract 20 16 prog)]
         [placeholder (extract 21 21 prog)]
         [shift (extract 23 22 prog)]
         [placeholder2 (extract 28 24 prog)]
         [s (extract 29 29 prog)]
         [op (extract 30 30 prog)]
         [sf (extract 31 31 prog)]
         [d (bitvector->natural rd)]
         [n (bitvector->natural rn)]
         [m (bitvector->natural rm)]
         [datasize (if (= (bitvector->natural sf) 1)
                       64
                       32)]
         [sub_op (= (bitvector->natural op) 1)]
         [setflags (= (bitvector->natural s) 1)])
    (if (= (bitvector->natural shift) 3)
        (emulator-undefined)
        (if (and (= (bitvector->natural sf) 0) (= (bitvector->natural (extract 5 5 sf)) 1))
            (emulator-undefined)
            ;; execute stage where we get the first two operands and then calculate the appropriate result
            (let* ([shift_amount (bitvector->natural imm6)]
                   [operand1 (vector-ref (aarch64state-regs state) d)]
                   [operand2 (if (= sub_op #t)
                                 (bvnot (car (ShiftReg m shift shift_amount)))
                                 (ShiftReg m shift shift_amount))]
                   [carry_in (if (= sub_op #t)
                                 (bv 1 1)
                                 (bv 0 1))]
                   [result (AddWithCarry operand1 operand2 carry_in)]
                   [additionResult (car result)]
                   [flagList (cdr result)])
              ; let statements can have multiple bodies (you don't need an explicit (begin ...))
              (when setflags
                (set-aarch64state-N! state (vector-ref flagList 0))
                (set-aarch64state-Z! state (vector-ref flagList 1))
                (set-aarch64state-C! (vector-ref flagList 2))
                (set-aarch64state-V! (vector-ref flagList 3)))
              ;; set result register to value 
              (vector-set! (aarch64state-regs state) d additionResult))))))

(define (AddWithCarry x y carry_in)
  (let* ([unsignedSum (+ (bitvector->natural x) (bitvector->natural y) (bitvector->natural carry_in))]
        [signedSum (+ (bitvector->integer x) (bitvector->integer y) (bitvector->natural carry_in))]
        [result (extract 63 0 (bv unsignedSum 64))]
        [n (extract 63 result)]
        [z (if (= (bitvector->natural result) 0)
               (bv 1 1)
               (bv 0 1))]
        [c (if (= (bitvector->natural result) unsignedSum)
               (bv 0 1)
               (bv 1 1))]
        [v (if (= (bitvector->integer result) signedSum)
               (bv 0 1)
               (bv 1 1))])
    (cons result (list->vector (list n z c v)))))

(define (ShiftReg reg type amount state)
  (let ([typeValue (bitvector->natural type)]
        [result (vector-ref (aarch64state-regs state) reg)])
    (cond [(= typeValue 0) (LSL result amount)]
          [(= typeValue 1) (LSR result amount)]
          [(= typeValue 2) (ASR result amount)]
          [(= typeValue 3) (ROR result amount)]
          [#t (emulator-undefined)])))

(define (LSL_C x shift)
  (if (> shift 0)
      (let ([result (bvshl x shift)]
            [carry_out (extract (- 64 shift) (- 64 shift) x)])
        (cons result carry_out))
      (emulator-undefined)))

(define (LSL x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (LSL_C x shift))
      (emulator-undefined)))

(define (LSR_C x shift)
  (if (> shift 0)
      (let* ([extended (zero-extend x (bitvector (+ shift 64)))]
            [result (extract (+ 63 shift) shift extended)]
            [carry_out (extract (- shift 1) (- shift 1) extended)])
        (cons result carry_out))
      (emulator-undefined)))

(define (LSR x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (LSR_C x shift))
      (emulator-undefined)))

(define (ASR_C x shift)
  (if (> shift 0)
      (let* ([extended (sign-extend x (bitvector (+ shift 64)))]
            [result (extract (+ shift 63) shift extended)]
            [carry_out (extract (- shift 1) (- shift 1) extended)])
        (cons result carry_out))
      (emulator-undefined)))

(define (ASR x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (ASR_C x shift))
      (emulator-undefined)))

(define (ROR_C x shift)
  (if (not (= shift 0))
      (let* ([m (modulo shift 64)]
            [result (bvor (car (LSR x m)) (car (LSL x (- 64 m))))]
            [carry_out (extract 63 result)])
        (cons result carry_out))
      (emulator-undefined)))

(define (ROR x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (ROR_C x shift))
      (emulator-undefined)))
