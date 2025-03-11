# Toy Assembly Suite
A pack of programs that compile, debug and execute a custom 32-bit assembly instruction-set inspired by the 6502 chip.

Fully written in Zig.

## - The Assembler
Responsible for taking an assembly source file as input and outputting a rom binary file that can be executed by the virtual machine or debugger.

## - The Debugger
Coming soon!

## - The Virtual Machine
Coming soon!

---

## Build

### Dependencies
* Zig version 0.14.0 or higher

### Build Commands
To build the Assembler, Debugger and Virtual Machine binary executables simply use a Zig build command in any directory inside the project.

Which type of executable you need is completely up to you, Zig provides 4 choices by default:

* (Recommended) Safe version, in case you need optimizations as well as runtime safety
```sh
zig build --release=safe
```

* Fast version, the highly optimized non-debug release version with minimal runtime safety checks
```sh
zig build --release=fast
```

* Small version, if you care about binary executable file sizes
```sh
zig build --release=small
```

* Debug version
```sh
zig build
```

## Run
The emitted executables should be in the zig-out/bin/ directory, run the binary with the "-h" flag for more help information regarding the program's specifications.
