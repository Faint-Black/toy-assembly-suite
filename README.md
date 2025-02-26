# Toy Assembly Suite
A pack of programs that compile, debug and execute a custom assembly instruction-set inspired by the 6502 chip.

Completely written in Zig.

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

* Fast release version
```sh
zig build --release=fast
```

* Safe release version
```sh
zig build --release=safe
```

* Small release version
```sh
zig build --release=small
```

---

## The Assembler
Responsible for taking an assembly source file as input and outputting a rom binary file that can be executed by the virtual machine.

## The Debugger
Coming soon!

## The Virtual Machine
Coming soon!
