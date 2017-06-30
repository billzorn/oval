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
