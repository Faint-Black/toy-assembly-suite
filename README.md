# Toy Assembly Suite
A pack of programs that compiles, debugs and executes a custom 32-bit assembly instruction-set inspired by the 6502 chip.

Fully written in Zig.

## - The Assembler
Responsible for taking an assembly source file as input and outputting a rom binary file that may be executed by the virtual machine on the debugger or runner.

## - The Debugger
Responsible for running or disassembling the input ROM file on a controlled virtual machine with many optional user options, mainly focused on logging the effects of the instructions rather than actually altering the machine state mid-execution.

## - The Runner
Coming soon!

---

## Build
*Requires Zig 0.14.0 or higher*

To build the Assembler, Debugger and Runner executables simply use the following Zig build command on any directory inside the project.

```sh
zig build --release=safe
```

## Run
The emitted executables should be in the zig-out/bin/ directory, run the binary with the "-h" flag for more help information regarding the program's specifications.
