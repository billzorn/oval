int test_intmax(int x)
{
    if(x + 1 > x)
    {
	return 0;
    }
    else
    {
	return 1;
    }
}

// 3 different interpretations by GCC:

// O0 does exactly what you would expect, making room
// on the stack to store X, and then laboriously
// comparing x+1, which is stored in a register,
// to the original value of x left on the stack.

// O1 is more clever, making use of lea to compute
// x+1 more efficiently and not bothering to put anything
// on the stack. However it still gets the right answer.

// O2 takes advantage of undefined behavior in C to just
// always return 0.

// 03 does the same thing as 02.

/*
example_undef_O0.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <test_intmax>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   89 7d fc                mov    %edi,-0x4(%rbp)
   7:   8b 45 fc                mov    -0x4(%rbp),%eax
   a:   83 c0 01                add    $0x1,%eax
   d:   3b 45 fc                cmp    -0x4(%rbp),%eax
  10:   7e 07                   jle    19 <test_intmax+0x19>
  12:   b8 00 00 00 00          mov    $0x0,%eax
  17:   eb 05                   jmp    1e <test_intmax+0x1e>
  19:   b8 01 00 00 00          mov    $0x1,%eax
  1e:   5d                      pop    %rbp
  1f:   c3                      retq   
*/

/*
example_undef_O1.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <test_intmax>:
   0:   8d 47 01                lea    0x1(%rdi),%eax
   3:   39 c7                   cmp    %eax,%edi
   5:   0f 9d c0                setge  %al
   8:   0f b6 c0                movzbl %al,%eax
   b:   c3                      retq   
*/

/*
example_undef_O2.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <test_intmax>:
   0:   31 c0                   xor    %eax,%eax
   2:   c3                      retq   
*/



// 2 interpretations by clang

// O0 is similar to GCC, but not as efficiently compiled.

// O1 and above have already identified the optimization
// and taken advantage of it. Notice the "nsw" attribute
// in the O0 llvm code.

/*
; ModuleID = 'example_undef.bc'
target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

; Function Attrs: nounwind uwtable
define i32 @test_intmax(i32 %x) #0 {
  %1 = alloca i32, align 4
  %2 = alloca i32, align 4
  store i32 %x, i32* %2, align 4
  %3 = load i32, i32* %2, align 4
  %4 = add nsw i32 %3, 1
  %5 = load i32, i32* %2, align 4
  %6 = icmp sgt i32 %4, %5
  br i1 %6, label %7, label %8

; <label>:7                                       ; preds = %0
  store i32 0, i32* %1, align 4
  br label %9

; <label>:8                                       ; preds = %0
  store i32 1, i32* %1, align 4
  br label %9

; <label>:9                                       ; preds = %8, %7
  %10 = load i32, i32* %1, align 4
  ret i32 %10
}

attributes #0 = { nounwind uwtable "disable-tail-calls"="false" "less-precise-fpmad"="false" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-feat
ures"="+fxsr,+mmx,+sse,+sse2" "unsafe-fp-math"="false" "use-soft-float"="false" }

!llvm.ident = !{!0}

!0 = !{!"clang version 3.8.0-2ubuntu4 (tags/RELEASE_380/final)"}


example_undef.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <test_intmax>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   89 7d f8                mov    %edi,-0x8(%rbp)
   7:   8b 7d f8                mov    -0x8(%rbp),%edi
   a:   83 c7 01                add    $0x1,%edi
   d:   3b 7d f8                cmp    -0x8(%rbp),%edi
  10:   0f 8e 0c 00 00 00       jle    22 <test_intmax+0x22>
  16:   c7 45 fc 00 00 00 00    movl   $0x0,-0x4(%rbp)
  1d:   e9 07 00 00 00          jmpq   29 <test_intmax+0x29>
  22:   c7 45 fc 01 00 00 00    movl   $0x1,-0x4(%rbp)
  29:   8b 45 fc                mov    -0x4(%rbp),%eax
  2c:   5d                      pop    %rbp
  2d:   c3                      retq   
*/

/*
; ModuleID = 'example_undef.bc'
target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

; Function Attrs: norecurse nounwind readnone uwtable
define i32 @test_intmax(i32 %x) #0 {
  ret i32 0
}

attributes #0 = { norecurse nounwind readnone uwtable "disable-tail-calls"="false" "less-precise-fpmad"="false" "no-frame-pointer-elim"="false" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+fxsr,
+mmx,+sse,+sse2" "unsafe-fp-math"="false" "use-soft-float"="false" }

!llvm.ident = !{!0}

!0 = !{!"clang version 3.8.0-2ubuntu4 (tags/RELEASE_380/final)"}


example_undef.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <test_intmax>:
   0:   31 c0                   xor    %eax,%eax
   2:   c3                      retq   
*/
