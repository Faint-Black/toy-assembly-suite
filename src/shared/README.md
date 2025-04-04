# Toy Assembly Standards
This shared module has common utils files made available for all programs in this repo, however it's mainly focused on defining the standard behavior of the toy assembly instruction set and it's execution.

## Sizes
This is an unsigned 32-bit assembly instruction set, meaning the CPU registers and all associated instructions that modify them may hold and perform arithmetic operations on any set of 32-bit numbers, however the address space of both ROM and RAM are limited to a measly 16-bit space. The are a lot of reasons for this design choice, the main one being conforming to a memory budget; only 0xFFFF bytes of instruction data and 0xFFFF bytes of accessible random access memory is more than enough for anyone deliberately using a *toy* assembly, shaving off those 2 bytes from each address related instruction saves up a lot more memory than you'd think. Another reason for this is creating two [0xFFFF+1]u8 arrays is much less taxing than two [0xFFFFFFFF+1]u8 arrays, allowing the entire virtual machine struct to be allocated on the stack.

## Address Spaces
ROM and WRAM do *not* share address spaces. Example: "LDA $0x1337" and "JMP $0x1337" do not point to the same space.

As a rule of thumb, every jumping/branching instruction uses the input address to point to an address inside ROM space, while every other instruction points to WRAM.

* The ROM
Since the maximum address space is only a 16-bits integer, the ROM can be up to 0xFFFF + 1 bytes long. Writing to ROM during the machine's execution should be completely impossible since the ROM and WRAM address spaces are completely isolated.

* The WRAM
Following the same length logic from the ROM, work RAM can be up to 0xFFFF + 1 bytes long. The user may modify it's contents as they wish.

* The Stack
The stack only has 0x0200 bytes of usable space, this choice value was chosen arbitrarily. Although it has a dedicated address space, it cannot be directly accessed by the user, the only instructions that alter the stack memory and stack pointer are the pushing instructions, popping instructions and subroutine instructions.

## Undefined Behavior Handling
There should be no undefined behavior in the debugger virtual machine or the release virtual machine. Edge cases are to be dealt with accordingly.

* WRAM out of bounds memory access:
Consider the following "LDA $0xFFFE" instruction, the virtual machine attempts to fetch 4 bytes of information from memory to put it in the accumulator, but it ends abruptly after 0xFFFF. The defined behavior for this is a simple integer wrap, thus the accumulator in the given example will load the bytes from these respective addresses:
```
LDA $0xFFFE
A = {$0xFFFE, $0xFFFF, $0x0000, $0x0001}
```

The same logic should apply to loading through indexing:
```
STRIDE 0x4

LDX 0x0
LDA $0xFFFB X
A = {$0xFFFB, $0xFFFC, $0xFFFD, $0xFFFE}

LDX 0x1
LDA $0xFFFB X
A = {$0xFFFF, $0x0000, $0x0001, $0x0002}

LDX 0x2
LDA $0xFFFB X
A = {$0x0003, $0x0004, $0x0005, $0x0006}
```

* ROM out of bounds memory access:
Incorrectly loading a ROM address is impossible. Run-time is not necessary.

* Stack out of bounds memory access:
Popping from an empty stack or pushing to a full stack should result in a crash or otherwise fatal error.
