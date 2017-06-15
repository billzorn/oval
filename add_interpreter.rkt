#lang rosette/safe
(require rosette/lib/match)

(struct instr (r1 r2 r3) #:transparent)
(struct add instr () #:transparent)

;; The state is a fixed-size vector of integers.
;; Looking up or mutating a register is just the corresponding vector-ref or vector-set!

;; A program is a (potentially variable-size) list of instrs,
;; all of which for now will be adds.

;; "running" a program takes the initial vector of registers and the list of
;; instructions, and mutates the registers in place.


;; update the state vector in place for this single instruction
(define (step state ins)
  (cond [(add? ins) (let ([v1 (vector-ref state (instr-r2 ins))]
                          [v2 (vector-ref state (instr-r3 ins))])
                      (begin
                        (vector-set! state (instr-r1 ins) (+ v1 v2))
                        '(vector-ref state (instr-r1))))]
        [#t state]))

(define (run state prog)
  (match prog
    [(cons ins rest)
     (begin
       (step state ins)
       (run state rest))]
    ['() state]
    [_ 'error]))


;; A little tricky - streams of unnamed symbolic values.
;; We need to redefine build-list and build-vector ourselves because
;; they aren't available from rosette/safe (ask yourself - why?).
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

;; This creates a new, unique symbolic value and returns it,
;; rather than introducing it with a definition.
(define (symbolic-integer)
  (define-symbolic* i integer?)
  i)

;; This builds a new (symbolic) state. Running a program with this state
;; is like running that program with all possible registers as inputs.
(define (new-state n)
  (build-vector n (lambda (i) (symbolic-integer))))


;; TODO: concrete test cases
(define t (list (add 1 2 3)))
(define t2 (list (add 1 2 3) (add 0 1 2)))
(define t3 (list (add 1 2 3)))



;; TODO: testing programs for equivalence
;; Check if two programs always return the same outputs for all possible inputs.
;; Assume that states always have the same number of registers, say 4.
;; If the programs always return the same outputs, return 'unsat, otherwise
;; return a counterexample of inputs that cause them to return different outputs.

(define (assert-regs-equal i vec1 vec2)
  (if (< i (vector-length vec1))
      (and (= (vector-ref vec1 i) (vector-ref vec2 i)) (assert-regs-equal (+ i 1) vec1 vec2))
      #t))

(define nregs 4)
(define (same-outputs prog1 prog2)
  (let* ([s1 (new-state nregs)]
        [s2 (clone-vector s1)])
    (run s1 prog1)
    (run s2 prog2)
    (printf "s1: ~a\ns2: ~a\n" s1 s2)
    (define assertion (not (assert-regs-equal 0 s1 s2)))
    (printf "asserting: ~a\n" assertion)
    (define sol (solve (assert assertion)))
    (if (unsat? sol)
        'equal
        sol)))

;;TODO:
;; implment dan's test case
;; bigger long chainings of adds some add properties to test
;; comment code
