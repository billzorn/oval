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
(struct ShiftType_LSL ())
(struct ShiftType_LSR ())
(struct ShiftType_ASR ())
(struct ShiftType_ROR ())

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
         [placeholder (bv 0 1)]
         [shift (extract 23 22 prog)]
         [placeholder2 (bv 11 5)]
         [s (bv 0 1)]
         [op (bv 1 1)]
         [sf (extract 31 31 prog)]
         [d (UInt rd)]
         [n (UInt rn)]
         [m (UInt rm)]
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
            (let* ([shift_type (DecodeShift shift)]
                   [shift_amount (UInt imm6)]
                   [operand1 (X (aarch64state-regs state) d datasize)]
                   [operand2 (if (= sub_op #t)
                                 (bvnot (ShiftReg m shift_type shift_amount))
                                 (ShiftReg m shift_type shift_amount))]
                   [carry_in (if (= sub_op #t)
                                 (bv 1 1)
                                 (bv 0 1))]
                   [result (AddWithCarry operand1 operand2 carry_in)]
                   [additionResult (car result)]
                   [flags (cdr result)])
              ; let statements can have multiple bodies (you don't need an explicit (begin ...))
              (when setflags
                (set-aarch64state-N! state (extract 0 0 flags))
                (set-aarch64state-Z! state (extract 1 1 flags))
                (set-aarch64state-C! state (extract 2 2 flags))
                (set-aarch64state-V! state (extract 3 3 flags)))
              ;; set result register to value
              (X! (aarch64state-regs state) d additionResult))))))


;; AddWithCarry
;; ============

(define (AddWithCarry x y carry_in)
  (let* ([N (bitvector-size (type-of x))]
         [unsignedSum (+ (UInt x) (UInt y) (UInt carry_in))]
         [signedSum (+ (SInt x) (SInt y) (UInt carry_in))]
         [result (extract (- N 1) 0 (bv unsignedSum N))]
         [n (extract 63 result)]
         [z (if (IsZero result)
                (bv 1 1)
                (bv 0 1))]
         [c (if (= (UInt result) unsignedSum)
                (bv 0 1)
                (bv 1 1))]
         [v (if (= (SInt result) signedSum)
                (bv 0 1)
                (bv 1 1))])
    (cons result (concat n z c v))))


;; ShiftReg
;; ===========

(define (ShiftReg reg type amount state)
  (let ([result (vector-ref (aarch64state-regs state) reg)])
    (cond [(ShiftType_LSL? type) (LSL result amount)]
          [(ShiftType_LSR? type) (LSR result amount)]
          [(ShiftType_ASR? type) (ASR result amount)]
          [(ShiftType_ROR? type) (ROR result amount)]
          [#t (emulator-undefined)])))


;; UInt()
;; ======

(define (UInt x)
  (bitvector->natural x))


;; SInt()
;; ======

(define (SInt x)
  (bitvector->integer x))


;; IsZero()
;; ========

(define (IsZero x)
  (= (bitvector->natural x) 0))


;; DecodeShift
;; ===========

(define (DecodeShift op)
  (let ([value (bitvector->natural op)])
    (cond [(= value 0) (ShiftType_LSL)]
          [(= value 1) (ShiftType_LSR)]
          [(= value 2) (ShiftType_ASR)]
          [(= value 3) (ShiftType_ROR)]
          [#t (emulator-undefined)])))

;; LSL_C
;; ===========

(define (LSL_C x shift)
  (let ([N (bitvector-size (type-of x))])
    (if (> shift 0)
        (let* ([extended_x (concat x (Zeros shift))]
               [result (extract (- N 1) 0 extended_x)]
               [carry_x (extract N N extended_x)])
          (cons result carry_x))
        (emulator-undefined))))


;; LSL
;; ===========

(define (LSL x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (car (LSL_C x shift)))
      (emulator-undefined)))


;; LSR_C
;; ===========

(define (LSR_C x shift)
  (let ([N (bitvector-size (type-of x))])
    (if (> shift 0)
        (let* ([extended_x (ZeroExtend x (bitvector (+ shift N)))]
               [result (extract (+ (- N 1) shift) shift extended_x)]
               [carry_out (extract (- shift 1) (- shift 1) extended_x)])
          (cons result carry_out))
        (emulator-undefined))))
  

;; LSR
;; ===========

(define (LSR x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (car (LSR_C x shift)))
      (emulator-undefined)))



;; ASR_C
;; ===========

(define (ASR_C x shift)
  (let ([N (bitvector-size (type-of x))])
    (if (> shift 0)
        (let* ([extended_x (SignExtend x (+ shift N))]
               [result (extract (+ shift (- N 1)) shift extended_x)]
               [carry_out (extract (- shift 1) (- shift 1) extended_x)])
          (cons result carry_out))
        (emulator-undefined))))


;; ASR
;; ===========
(define (ASR x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (car (ASR_C x shift)))
      (emulator-undefined)))



;; ROR_C
;; ===========

(define (ROR_C x shift)
  (let ([N (bitvector-size (type-of x))])
    (if (not (= shift 0))
        (let* ([m (modulo shift N)]
               [result (bvor (LSR x m) (LSL x (- N m)))]
               [carry_out (extract (- N 1) result)])
          (cons result carry_out))
        (emulator-undefined))))


;; ROR
;; ===========

(define (ROR x shift)
  (if (>= shift 0)
      (if (= shift 0)
          x
          (car (ROR_C x shift)))
      (emulator-undefined)))



;; X[] - assignment form
;; =====================
;; Write to general-purpose register from either a 32-bit or a 64-bit value.

(define (X! regs n value)
  (let ([width (bitvector-size (type-of value))])
    (if (and (>= n 0) (<= n 31) (or (= width 32) (= width 64)) (not (= n 31)))
        (vector-set! regs n (ZeroExtend value (bitvector-size (type-of (vector-ref regs n)))))
        (emulator-undefined))))



;; X[] - non-assignment form
;; =========================
;; Read from general-purpose register with implicit slice of 8, 16, 32 or 64 bits.

(define (X regs n width)
  (if (and (>= n 0) (<= n 31) (or (= width 8) (= width 16) (= width 32) (= width 64)))
      (if (not (= n 31))
          (extract (- width 1) 0 (vector-ref regs n))
          (Zeros width))
      (emulator-undefined)))


;; Replicate()
;; ===========


;; Zeros()
;; =======

(define (Zeros N)
  (bv 0 N))


;; ZeroExtend()
;; ============

(define (ZeroExtend x N)
  (let ([M (bitvector-size (type-of x))])
    (if (>= N M)
        (concat (Zeros (- N M)) x)
        (emulator-undefined))))


;; SignExtend()
;; ============

(define (SignExtend x N)
  (sign-extend x (bitvector N)))
