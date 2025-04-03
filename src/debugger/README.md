# Debugger
This is just a virtual machine with many extra features, allowing for easy step-by-step debugging, it isn't any gdb but gets the job done.

---

# Flags
The main features of the debuggers can be directly altered, disabled or enabled in the command line invocation.

Please note that the order of the flag arguments doesn't matter in the most part. Also there must be only one debugger mode flag active at one time.

## Run mode:
```sh
$ ./debugger -r --input="path/to/rom.bin"
```

The "-r" or "--run" flag enables the debugger run mode, which loads the ROM into a virtual machine and executes it, it is up to the user to define additional features, such as logging and changing the instruction delay.

## Disassembly mode:
```sh
$ ./debugger -d --input="path/to/rom.bin"
```

the "-d" or "--disassemble" flag enables the debugger disassembly mode, which turns the input ROM binary back into human readable instructions.
