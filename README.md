# Toy Assembly Suite
A pack of programs that compile, debug and execute a custom 32-bit assembly instruction-set inspired by the 6502 chip.

Fully written in Zig.

---

## Build

### Dependencies
* Zig version 0.14.0.dev

### Build Commands
To build the assembler, debugger or virtual machine simply cd into the desired project and use a build command.

Which type of executable you need is completely up to you, zig provides 4 choices by default:

* Debug version
```sh
zig build
```

* Fast version, the standard optimized non-debug release version
```sh
zig build --release=fast
```

* Safe version, in case you need optimizations as well as runtime safety
```sh
zig build --release=safe
```

* Small version, if you care about binary executable file sizes
```sh
zig build --release=small
```

## Running
The emitted executable binary should be in the zig-out/bin/ directory, run the binary with the "-h" flag for more help information regarding the program specifications.

---

## The Assembler
Responsible for taking an assembly source file as input and outputting a rom binary file that can be executed by the virtual machine.

## The Debugger
Coming soon!

## The Virtual Machine
Coming soon!
