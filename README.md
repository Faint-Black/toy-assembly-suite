# Toy Assembly Suite
A pack of programs that **compiles**, **debugs**, **disassembles** and **executes** a custom 32-bit assembly instruction-set inspired by the 6502 chip.

* The Assembler

Responsible for taking an assembly source file as input and outputting a rom binary file that may be executed by the virtual machine on the debugger or runner.

* The Debugger

Responsible for running the input ROM file on a controlled environment with many optional features, mainly focused on logging the effects of the instructions rather than actually altering the machine state mid-execution.

* The Disassembler

Responsible for turning a compiled ROM binary back into humanly readable instructions, most effective when ROMs have been compiled with debug metadata enabled.

* The Runner

Responsible for executing the compiled ROM in an optimized and minimal manner, e.g. no runtime debug logging.

---

## Build
*Requires Zig 0.14.0 or higher*

To build all the project executables simply use the following Zig build command on any directory inside the project.

```sh
zig build --release=safe
```

## Run
The emitted executables should be in the zig-out/bin/ directory, run the binary with the "-h" flag for more help information regarding the program's specifications.
