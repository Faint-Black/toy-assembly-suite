# Assembler
This turns your input source file of choice into a ROM file that can be executed in the virtual machine or debugger.

To get accustomed to the syntax, refer to the samples/ directory where there are plenty of source examples, specially "alltokens.txt".

---

# Internal execution model
Section reserved for documenting the execution model taking place inside the codebase.

## 1st step:
**(input file string) -> (lexed tokens)**

This is done during the "Lexer" function of the lexer module.

Turn the raw text received into usable tokens in memory.

input:
```
.macro MyMacro
  LDA 0xFF
  STA $0x42
.endmacro

NOP
MyMacro
CMP A X
BEQ
Skip:
BRK
```

output:
```
{
MACRO, IDENTIFIER="MyMacro", $
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
ENDMACRO, $
NOP, $
IDENTIFIER="MyMacro"
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

symbol table:
```
empty.
```

## 2nd step:
**(lexed tokens) -> (stripped tokens)**

This is done during the "First Pass" function in the preprocessor module.

Remove the preprocessor definitions, such as macros, and add them to the global identifier symbol table. It also adds the labels to the symbol table under a placeholder address position, so forward referencing may occur during codegen, the correct address position is only defined during Second Pass of codegen.

input:
```
{
MACRO, IDENTIFIER="MyMacro", $
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
ENDMACRO, $
NOP, $
IDENTIFIER="MyMacro"
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

output:
```
{
NOP, $
IDENTIFIER="MyMacro"
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

symbol table:
```
symbol #0
name: "MyMacro"
type: macro
expands to:
{
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
}

symbol #1
name: "Skip"
type: label
address value: 0x00
```

## 3rd step:
**(stripped tokens) -> (expanded tokens)**

This is done during the "Second Pass" function in the preprocessor module.

Substitute the preprocessor identifiers, perform the macro unwrapping.

input:
```
{
NOP, $
IDENTIFIER="MyMacro"
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

output:
```
{
NOP, $
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

symbol table:
```
symbol #0
name: "MyMacro"
type: macro
expands to:
{
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
}

symbol #1
name: "Skip"
type: label
address value: 0x00
```

## 4th step:

### First Pass
**(expanded tokens) -> void**

This is done during the "Codegen" function in the codegen module.

The first pass does more or less the same of what the second pass does, however the bytecode is only generated so the label address values may be calculated and properly replaced in the global symbol table, this is necessary for forward referencing.

input:
```
{
NOP, $
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

symbol table:
```
symbol #0
name: "MyMacro"
type: macro
expands to:
{
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
}

symbol #1
name: "Skip"
type: label
address value: 0x1A
```

### Second Pass
**(expanded tokens) -> (rom bytecode)**

This is done during the "Codegen" function in the codegen module.

Turn the tokens in their finalized state into a byte array representing the rom bytecode meant to be executed on the virtual machine or debugger.

input:
```
{
NOP, $
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
CMP, A, X, $
BEQ, $
LABEL="Skip", $
BRK, $
}
```

output:
```
{0x69, 0x01, 0x10, 0x00, 0xCC, 0xCC, ...}
```

symbol table:
```
symbol #0
name: "MyMacro"
type: macro
expands to:
{
LDA, LIT=0xFF, $
STA, ADDR=0x42, $
}

symbol #1
name: "Skip"
type: label
address value: 0x1A
```

---

# TODO list
- [X] on march 3rd Zig 0.14 will be fully released, update codebase accordingly.
- [X] implement (run-time) visibility toggles for debug information
- [X] clean the lone newline token created by macros
- [X] set address bytecode size to 16-bit
- [X] implement ".repeat n"
- [X] implement ".define"
- [X] anonymous and relative labels
- [X] add assembler README.md
- [X] implement baked-in debug symbols
- [X] refine unit tests
- [X] implement "--noprint=[ARG]" flags
- [X] clean up codebase for the 1.0 release
