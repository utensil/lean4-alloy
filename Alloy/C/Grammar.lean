/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Alloy.Util.Parser
import Alloy.Util.Grammar

/-!
# The C Grammar

This module contains a Lean DSL that encodes the standard C syntax.

It uses Microsoft's [C Language Syntax Summary][1], the C11 standard's
[specification][2], and cppreference's [C language][3] as guidelines.

[1]: https://docs.microsoft.com/en-us/cpp/c-language/c-language-syntax-summary
[2]: https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf#page=476
[3]: https://en.cppreference.com/w/c/language
-/

open Lean Parser

register_option Alloy.C.optSemicolon : Bool := {
  defValue := true
  descr := "Should semicolons be optional in Alloy C code?"
}

namespace Alloy.C

/-!
## Basic Abstractions

We need to forward declare these in order to construct the syntax `type`
which is used by the cast expression syntax (`castExpr`).

A good reference on the C representation of types is:
https://blog.robertelder.org/building-a-c-compiler-type-system-a-canonical-type-representation/

**Implementation Note:** Syntax categories are currently defined
with  `behavior := both` rather than the ideal `behavior := symbol` due to
[lean4#2608][https://github.com/leanprover/lean4/issues/2608].
-/

/--
A `specifier-qualifier` of the C grammar,
which includes an `alignment-specifier` in Microsoft's C standard.
-/
declare_syntax_cat cSpec (behavior := both)

/-- A `type-specifier` of the C grammar. -/
declare_syntax_cat cTypeSpec (behavior := both)

syntax cTypeSpec : cSpec

/-- A `type-qualifier` of the C grammar. -/
declare_syntax_cat cTypeQ (behavior := both)

syntax cTypeQ : cSpec

/-- A `pointer` of the C grammar. -/
syntax pointer := (" * " cTypeQ*)+

/-- A `direct-declarator` of the C grammar. -/
declare_syntax_cat cDirectDeclarator (behavior := both)

/-- A `direct-abstract-declarator` of the C grammar. -/
declare_syntax_cat cDirectAbsDeclarator (behavior := both)

/-- A `declarator` of the C grammar. -/
syntax declarator := «pointer»? cDirectDeclarator

/-- An `abstract-declarator` of the C grammar. -/
syntax absDeclarator := (pointer «cDirectAbsDeclarator»?) <|> cDirectAbsDeclarator

/-- A [`type`](https://en.cppreference.com/w/c/language/type) of the C grammar. -/
syntax type := cSpec+ optional(absDeclarator)

/--
An `assignment-expression` of the C grammar.
That is, a single (not comma separated) C `expression`.
-/
declare_syntax_cat cExpr (behavior := both)

/--
A [`constant-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/constant_expression
-/
syntax constExpr := cExpr:20

/-- A `designator` of the C grammar. -/
declare_syntax_cat cDesignator

/-- An `initializer` of the C grammar. -/
declare_syntax_cat cInitializer

/-- Designates the index of a C array to initialize. -/
syntax "[" constExpr "]" : cDesignator

/-- Designates the field of a C aggregate to initialize. -/
syntax "." ident : cDesignator

/-- A C initializer that uses an expression. -/
syntax cExpr : cInitializer

/-- An element of a C initializer list. -/
syntax initializerElem := optional(cDesignator+ "=") cInitializer

/-- A C aggregate initializer that uses an initializer list. -/
syntax "{" initializerElem,*,? "}" : cInitializer

/--
A [`statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements
-/
declare_syntax_cat cStmt (behavior := both)

/--
A top-level C language command
(i.e., a preprocessor directive or external declaration).
-/
declare_syntax_cat cCmd (behavior := both)

--------------------------------------------------------------------------------
/-! ## Comments                                                               -/
--------------------------------------------------------------------------------

variable (pushMissingOnError : Bool) in
/-- Adaption of `Lean.Parser.finishCommentBlock`. -/
partial def finishCommentBlock (nesting : Nat) : ParserFn := fun c s =>
  let input := c.input
  let i     := s.pos
  if h : input.atEnd i then eoi s
  else
    let curr := input.get' i h
    let i    := input.next' i h
    if curr == '*' then
      if h : input.atEnd i then eoi s
      else
        let curr := input.get' i h
        if curr == '/' then -- "-/" end of comment
          if nesting == 1 then s.next' input i h
          else finishCommentBlock (nesting-1) c (s.next' input i h)
        else
          finishCommentBlock nesting c (s.setPos i)
    else if curr == '/' then
      if h : input.atEnd i then eoi s
      else
        let curr := input.get' i h
        if curr == '-' then finishCommentBlock (nesting+1) c (s.next' input i h)
        else finishCommentBlock nesting c (s.setPos i)
    else finishCommentBlock nesting c (s.setPos i)
where
  eoi s := s.mkUnexpectedError (pushMissing := pushMissingOnError) "unterminated comment"

def blockCommentBody :=
  raw (finishCommentBlock (pushMissingOnError := true) 1) (trailingWs := true)

/-- A C line comment. -/
syntax lineComment := "//" Alloy.line

/-- A C block comment. -/
syntax blockComment := "/*" blockCommentBody

attribute [cCmd_parser, cStmt_parser, cExpr_parser]
  lineComment blockComment

syntax atomic(lineComment) cStmt : cStmt
syntax atomic(blockComment) cStmt : cStmt
syntax cStmt lineComment : cStmt
syntax cStmt blockComment : cStmt

syntax atomic(lineComment) cExpr : cExpr
syntax atomic(blockComment) cExpr : cExpr
syntax cExpr lineComment : cExpr
syntax cExpr blockComment : cExpr

--------------------------------------------------------------------------------
/-! ## Expressions                                                            -/
--------------------------------------------------------------------------------

/-!
### Primary Expressions

Collectively (mostly) encode a `primary-expression` of the C grammar.
-/

/--
A C identifier implemented with a Lean identifier.
Thus, it will also capture simple member accesses and prefixed character
constants.
-/
syntax:max ident : cExpr

/--
A C `integer-suffix` of a [`integer-constant`][1].
Can be an upper- or lower-case `l` or `ll` with a `u` prefix or suffix.

[1]: https://en.cppreference.com/w/c/language/integer_constant
-/
def intSuffix :=
  identSatisfy ["integer suffix"] fun
  | .str .anonymous s =>
    let s := s.toLower
    let s :=
      if s.front = 'u' then s.drop 1
      else if s.back = 'u' then s.dropRight 1
      else s
    s = "l" || s = "ll"
  | _ => false

/--
A C [`integer-constant`][1] implemented with a Lean numeric literal.

[1]: https://en.cppreference.com/w/c/language/integer_constant
-/
syntax:max (name := intConst) num (noWs intSuffix)? : cExpr

/--
A C [`floating-constant`][1] implemented with a Lean scientific literal.
Thus, it does not currently support hexadecimal floating constants.

[1]: https://en.cppreference.com/w/c/language/floating_constant
-/
syntax:max (name := floatConst) scientific (noWs (&"f" <|> &"F" <|> &"l" <|> &"L"))? : cExpr

/--
A C [`character-constant`][1] implemented with a Lean character literal.
Thus, it thus does not currently support prefixed or multicharacter constants.

[1]: https://en.cppreference.com/w/c/language/character_constant
-/
syntax:max (name := charConst) char : cExpr

/-- A C [`string-literal`](https://en.cppreference.com/w/c/language/string_literal). -/
syntax:max ((&"u8" <|> &"u" <|> &"U" <|> &"L") noWs)? str : cExpr

/-- A C [compound literal](https://en.cppreference.com/w/c/language/compound_literal). -/
syntax:max "(" type ")" "{" initializerElem,*,? "}" : cExpr

/-- A C parenthetical expression. -/
syntax:max "(" cExpr ")" : cExpr

/-- A `generic-association` of the C grammar. -/
syntax genericAssoc := (ident ":" cExpr) <|> (&"default" ":" cExpr)

/-- A `generic-selection` expression of the C grammar (since C11). -/
syntax:max "_Generic" "(" cExpr "," genericAssoc,+ ")" : cExpr

/-!
### Postfix Expressions

Collectively encode a `postfix-expression` of the C grammar.
-/

/--
A C [subscript][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_member_access#Subscript
-/
syntax:1000 cExpr:1000 "[" cExpr "]" : cExpr

/--
A C [functional call][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_other#Function_call
-/
syntax:1000 cExpr:1000 "(" cExpr,* ")" : cExpr

/--

A C++ [new][1] expression.

[1]: https://en.cppreference.com/w/cpp/language/new

Supports only: `new S`.

TODO: Move to Cpp module, and include all new variants.

-/
syntax:1000 "new" type : cExpr

/--

A C++ [delete][1] expression.

[1]: https://en.cppreference.com/w/cpp/language/delete

Supports only: `delete (S*)ptr`.

TODO: Move to Cpp module, and include all delete variants.

-/
syntax:1000 "delete" cExpr:1000 : cExpr

/--
A C [member access][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_member_access#Member_access
-/
syntax:1000 cExpr:1000 "." ident : cExpr

/--
A C [member access through pointer][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_member_access#Member_access_through_pointer
-/
syntax:1000 cExpr:1000 "->" ident : cExpr

/--
A C [increment][1] postfix expression.
The result of the expression is the original value of the operand.

[1]: https://en.cppreference.com/w/c/language/operator_incdec
-/
syntax:1000 cExpr:1000 "++" : cExpr

/--
A C [decrement][1] postfix expression.
The result of the expression is the original value of the operand.

[1]: https://en.cppreference.com/w/c/language/operator_incdec
-/
syntax:1000 cExpr:1000 "--" : cExpr

/-!
### Unary Expressions

Collectively encode a `unary-expression` of the C grammar.
-/

/--
An C [increment][1] prefix expression.
The result of the expression is the incremented value of the operand.

[1]: https://en.cppreference.com/w/c/language/operator_incdec
-/
syntax:500 "++" cExpr:500 : cExpr

/--
An C [decrement][1] prefix expression.
The result of the expression is the decremented value of the operand.

[1]: https://en.cppreference.com/w/c/language/operator_incdec
-/
syntax:500 "--" cExpr:500 : cExpr

/--
A C [`address-of`][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_member_access#Address_of
-/
syntax:500 "&" cExpr:100 : cExpr

/--
A C [pointer dereference][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_member_access#Deference
-/
syntax:500 "*" cExpr:100 : cExpr

/--
A C [unary plus][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Unary_arithmetic
-/
syntax:500 "+" cExpr:100 : cExpr

/--
A C [unary minus][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Unary_arithmetic
-/
syntax:500 "-" cExpr:100 : cExpr

/--
A C [bitwise NOT][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Bitwise_logic
-/
syntax:500 "~" cExpr:100 : cExpr

/--
A C [logical NOT][1] expression.

[1]: https://en.cppreference.com/w/c/language/operator_logical#Logical_NOT
-/
syntax:500 "!" cExpr:100 : cExpr

/--
A C [`sizeof`][1] expression.
Returns the size, in bytes, of the [object representation][2]
of the provided type or the type of the provided expression.

[1]: https://en.cppreference.com/w/c/language/sizeof
[2]: https://en.cppreference.com/w/c/language/object#Object_representation
-/
syntax:500 "sizeof" (atomic("(" type ")") <|> cExpr:500) : cExpr

/--
A C [`_Alignof`][1] expression.
Returns the [alignment requirement][2] of the provided type.

[1]: https://en.cppreference.com/w/c/language/_Alignof
[2]: https://en.cppreference.com/w/c/language/object#Alignment
-/
syntax:500 "_Alignof" "(" type ")" : cExpr


/-!
### Cast Expression
-/

/-- A [`cast-expression`](https://en.cppreference.com/w/c/language/cast) of the C grammar. -/
syntax castExpr := "(" type ")" cExpr:100
attribute [cExpr_parser 100] castExpr

/-!
### Multiplicative Expressions

Collectively encode a [`multiplicative-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Multiplicative_operators
-/

/-- A C multiplication expression. -/
syntax:70 (name := mulExpr) cExpr:70 " * " cExpr:71 : cExpr

/-- A C division expression. -/
syntax:70 (name := divExpr) cExpr:70 " / " cExpr:71 : cExpr

/-- A C remainder expression. -/
syntax:70 (name := remExpr) cExpr:70 " % " cExpr:71 : cExpr

/-!
### Additive Expressions

Collectively encode an [`additive-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Additive_operators
-/

/-- A C addition expression. -/
syntax:65 (name := addExpr) cExpr:65 " + " cExpr:66 : cExpr

/-- A C subtraction expression. -/
syntax:65 (name := subExpr) cExpr:65 " - " cExpr:66 : cExpr

/-!
### Shift Expressions

Collectively encode a [`shift-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Shift_operators
-/

/-- A C left shift expression. Left shifts the LHS by RHS bits.  -/
syntax:60 (name := shlExpr) cExpr:60 " << " cExpr:61 : cExpr

/-- A C right shift expression. Right shifts the LHS by RHS bits.  -/
syntax:60 (name := shrExpr) cExpr:60 " >> " cExpr:61 : cExpr

/-!
### Relational Expressions

Collectively encode a [`relational-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_comparison#Relational_operators
-/

/-- A C less-than expression. -/
syntax:55 (name := ltExpr) cExpr:55 " < " cExpr:56 : cExpr

/-- A C greater-than expression. -/
syntax:55 (name := gtExpr) cExpr:55 " > " cExpr:56 : cExpr

/-- A C less-or-equal expression. -/
syntax:55 (name := leExpr) cExpr:55 " <= " cExpr:56 : cExpr

/-- A C greater-or-equal expression. -/
syntax:55 (name := geExpr) cExpr:55 " >= " cExpr:56 : cExpr


/-!
### Equality Expressions

Collectively encode an [`equality-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_comparison#Equality_operators
-/

/-- A C equal-to expression. -/
syntax:50 (name := eqExpr) cExpr:50 " == " cExpr:51 : cExpr

/-- A C not-equal-to expression. -/
syntax:50 (name := neExpr) cExpr:50 " != " cExpr:51 : cExpr

/-!
### Bitwise Expressions

Collectively encodes the [binary bitwise operators][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_arithmetic#Bitwise_logic
-/

/-- An `AND-expression` of the C grammar. -/
syntax:45 (name := andExpr) cExpr:45  " & " cExpr:46 : cExpr

/-- An `exclusive-OR-expression` of the C grammar. -/
syntax:43 (name := xorExpr) cExpr:43  " ^ " cExpr:44 : cExpr

/-- An `inclusive-OR-expression` of the C grammar. -/
syntax:40 (name := orExpr) cExpr:40 " | " cExpr:41 : cExpr

/-!
### Logical Expressions

Collectively encodes the [binary logical operators][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_logical
-/

/-- A `logical-AND-expression` of the C grammar. -/
syntax:35 (name := logicalAndExpr) cExpr:35 " && " cExpr:36 : cExpr

/-- A `logical-OR-expression` of the C grammar. -/
syntax:30 (name := logicalOrExpr) cExpr:30 " || " cExpr:31 : cExpr

/-!
### Conditional Expression
-/

/--
A [`conditional-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_other#Conditional_operator
-/
syntax:20 (name := condExpr) cExpr:21 " ? " cExpr,+ " : " cExpr:20 : cExpr

/-!
### Assignment Expression

C assignment and compound assignment expressions are binary operations
that modify the variable on the LHS using the value on the RHS.
-/

/-- An `assignment-operator` of the C grammar. -/
declare_syntax_cat cAssignOp

syntax " = " : cAssignOp
syntax " *= " : cAssignOp
syntax " /= " : cAssignOp
syntax " %= " : cAssignOp
syntax " += " : cAssignOp
syntax " -= " : cAssignOp
syntax " <<= " : cAssignOp
syntax " >>= " : cAssignOp
syntax " &= " : cAssignOp
syntax " ^= " : cAssignOp
syntax " |= " : cAssignOp

/--
A non-conditional [`assignment-expression`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/operator_assignment
-/
syntax:15 (name := assignExpr) cExpr:500 cAssignOp cExpr:15 : cExpr

--------------------------------------------------------------------------------
/-! ## Declaration Syntax                                                     -/
--------------------------------------------------------------------------------

/-!
### Specifiers
-/

/-- A `declaration-specifier` of the C grammar. -/
declare_syntax_cat cDeclSpec

syntax cSpec : cDeclSpec

/-- A GNU-style attribute specifier for a declaration. -/
syntax "__attribute__" noWs "(" "(" (rawIdent ("(" cExpr,* ")")?),* ")" ")" : cDeclSpec

/-!
#### Storage Class Specifiers
-/

/--
A [`storage-class-specifier`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/storage_duration
-/
declare_syntax_cat cStorageClassSpec (behavior := both)

/-- The C automatic storage duration specifier. -/
syntax "auto" : cStorageClassSpec

/-- The C external linkage specifier. -/
syntax "extern" : cStorageClassSpec

/-- The C register storage hint specifier. -/
syntax "register" : cStorageClassSpec

/-- The C static storage duration and internal linkage specifier. -/
syntax "static" : cStorageClassSpec

/-- The C thread storage duration specifier. -/
syntax "_Thread_local" : cStorageClassSpec

/-- The C [typedef](https://en.cppreference.com/w/cpp/language/typedef) specifier. -/
syntax "typedef" : cStorageClassSpec

syntax cStorageClassSpec : cDeclSpec

/-!
#### Function Specifiers
-/

/--
A [`function-specifier`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/function_specifiers
-/
declare_syntax_cat cFunSpec (behavior := both)

/-- The C [inline](https://en.cppreference.com/w/c/language/inline) function specifier.-/
syntax "inline" : cFunSpec

/-- The C [_Noreturn](https://en.cppreference.com/w/c/language/_Noreturn) function specifier. -/
syntax "_Noreturn" : cFunSpec

syntax cFunSpec : cDeclSpec

/-!
### Declarators
-/

declare_syntax_cat cIndex

syntax cExpr : cIndex
syntax "static" cTypeQ* cExpr : cIndex
syntax cTypeQ+ "static"? cExpr : cIndex
syntax cTypeQ* "*" : cIndex

/-- A `parameter-declaration` of the C grammar. -/
syntax paramDecl := cDeclSpec+ (atomic(declarator) <|> absDeclarator)?

/-- A `parameter-type-list` of the C grammar. -/
syntax params := paramDecl,+,? "..."?

/-- The name of a declaration. -/
syntax:max ident : cDirectDeclarator

syntax:max "(" declarator ")" : cDirectDeclarator
syntax:arg cDirectDeclarator:arg "[" optional(cIndex) "]" : cDirectDeclarator
syntax:arg cDirectDeclarator:arg "(" params ")" : cDirectDeclarator
syntax:arg cDirectDeclarator:arg "(" ident* ")" : cDirectDeclarator

syntax:max "(" absDeclarator ")" : cDirectAbsDeclarator
syntax:max "(" params ")" : cDirectAbsDeclarator
syntax:arg cDirectAbsDeclarator:arg "[" optional(cIndex) "]" : cDirectAbsDeclarator
syntax:arg cDirectAbsDeclarator:arg "(" optional(params) ")" : cDirectAbsDeclarator

/-!
### Declarations
-/

/--
The semicolon terminator of a C statement/declaration.

The semicolon is made "optional" to help make partial statements
well-formed for better LSP support and to enable whitespace-based termination
in polyglot syntax. This behavior can be disabled via
`set_option Alloy.C.optSemicolon false`.

For the shim, the elaborator will always convert this into a real semicolon,
even if it has been elided in user code.
-/
def endSemi : Parser := leading_parser
  withFn (p := optional (symbol ";")) fun p c s =>
    if optSemicolon.get c.options then p c s else symbolFn ";" c s

/-- Ensure the previous syntax ended with a semicolon token. -/
def checkSemi : Parser :=
  checkStackTop (tailSyntax · |>.isToken ";") "expected ';'"

/-- An `init-declarator` of the C grammar. -/
syntax initDeclarator := declarator optional(" = " cInitializer)

/--
A [`declaration`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/declarations
-/
syntax declaration :=
  /-
  Recall that an `ident` can be a `cDeclSpec` or a `declarator`.
  The lookahead is needed to prevent Lean from robbing a `declarator`
  of its leading `ident`. For example, without it, `int x = 5;` would be
  parsed as  `int : cDeclSpec`, `x : cDeclSpec`, `= 5 : declarator`, which
  would error as `= 5` is not a valid declarator.

  Also note that in `int x;` the syntax kind of `x` is ambiguous in the C
  grammar -- it could be a `cDeclSpec` or a `declarator`.
  This parses it as a `declarator`.
  -/
  many1OptLookahead(cDeclSpec, declarator) initDeclarator,* endSemi

--------------------------------------------------------------------------------
/-! ## Types                                                                  -/
--------------------------------------------------------------------------------

/-!
### Qualifiers
-/

/-- The C [const](https://en.cppreference.com/w/c/language/const) type qualifier. -/
syntax "const" : cTypeQ

/-- The C [restrict](https://en.cppreference.com/w/c/language/restrict) type qualifier. -/
syntax "restrict" : cTypeQ

/-- The C [volatile](https://en.cppreference.com/w/c/language/volatile) type qualifier. -/
syntax "volatile" : cTypeQ

/-- The C [_Atomic](https://en.cppreference.com/w/c/language/_Atomic) type qualifier. -/
syntax "_Atomic" : cTypeQ

/-!
### Primitives
-/

/-- The C `void` type. -/
syntax "void" : cTypeSpec

/-- The C `char` type. -/
syntax "char" : cTypeSpec

/-- The C `short` integer type. -/
syntax "short" : cTypeSpec

/-- The C `int` integer type. -/
syntax "int" : cTypeSpec

/--
The C `long` integer type or
`long` type specifier (e.g., `long long`, `long double`).
-/
syntax "long" : cTypeSpec

/--
The C single precision real floating-point type or
the single precision floating-point type specifier (e.g., `float _Complex`).
-/
syntax "float" : cTypeSpec

/--
The C double precision real floating-point type or
the single precision floating-point specifier (e.g., `double _Complex`).
-/
syntax "double" : cTypeSpec

/-- The C signed integer type specifier. -/
syntax "signed" : cTypeSpec

/-- The C unsigned integer type specifier. -/
syntax "unsigned" : cTypeSpec

/-- The C boolean type (since C99). -/
syntax "_Bool" : cTypeSpec

/-- The C complex type (since C99). -/
syntax "_Complex" : cTypeSpec

/-- The C imaginary type (since C99 if the implementation supports it). -/
syntax "_Imaginary" : cTypeSpec

/-- A user-defined C type. -/
syntax ident : cTypeSpec

/-!
### Atomic
-/

/-- An `atomic-type-specifier` of the C grammar. -/
syntax atomicSpec : cTypeSpec := "_Atomic" "(" type ")"

/-!
### Aggregates

Collective encodes the `struct-or-union-specifier` of the C grammar.
-/

/--
A C [bit field][1]. Defines the explicit width, in bits, of a member.

[1]: https://en.cppreference.com/w/c/language/bit_field
-/
syntax aggrDeclBits := " : " constExpr

/-- A `struct-declarator` of the C grammar. -/
syntax aggrDeclarator := aggrDeclBits <|> (declarator optional(aggrDeclBits))

/-- A `struct-declaration` of the C grammar. -/
syntax aggrDeclaration :=
  -- See `declaration` as to why the lookahead is needed.
  many1OptLookahead(cSpec, aggrDeclarator) aggrDeclarator,* endSemi

syntax aggrDef := "{" (lineComment <|> blockComment <|> aggrDeclaration)* "}"
syntax aggrSig := aggrDef <|> (ident optional(aggrDef))

/-- A C [struct](https://en.cppreference.com/w/c/language/struct) declaration. -/
syntax structSpec : cTypeSpec := "struct " aggrSig

/-- A C [union](https://en.cppreference.com/w/c/language/union) declaration. -/
syntax unionSpec : cTypeSpec := "union " aggrSig

/-!
### Enums
-/

/-- An [`enumerator`](https://en.cppreference.com/w/c/language/enum) of the C grammar. -/
syntax enumerator := ident optional(" = " constExpr)

syntax enumDef := "{" (lineComment <|> blockComment <|> enumerator),+ "}"
syntax enumSig := enumDef <|> (ident optional(enumDef))

/-- An [`enum-specifier`](https://en.cppreference.com/w/c/language/enum) of the C grammar. -/
syntax enumSpec : cTypeSpec := "enum " enumSig

/-!
### Alignment
-/

/-- An `alignment-specifier` of the C grammar. -/
syntax alignSpec : cSpec := &"_Alignas" "(" (type <|> constExpr) ")"

--------------------------------------------------------------------------------
/-! ## Statements                                                             -/
--------------------------------------------------------------------------------

/-!
### Jump Statements

Collectively encode a [`jump-statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements#Jump_statements
-/

/-- A C [goto](https://en.cppreference.com/w/c/language/goto) statement. -/
syntax gotoStmt : cStmt := &"goto " ident endSemi

/-- A C [continue](https://en.cppreference.com/w/c/language/continue) statement. -/
syntax continueStmt : cStmt := "continue" endSemi

/-- A C [break](https://en.cppreference.com/w/c/language/break) statement. -/
syntax breakStmt : cStmt := "break" endSemi

/-- A C [return](https://en.cppreference.com/w/c/language/return) statement. -/
syntax returnStmt : cStmt := "return" (ppSpace cExpr),* endSemi

/-!
### Compound Statements
-/

/--
Syntax which can be used in the place of a statement in a `compound-statement`.
This is a syntax category so as to prefer the longest match.
-/
declare_syntax_cat cStmtLike
syntax declaration : cStmtLike
syntax cStmt : cStmtLike

/-- A optionally indent-based sequence of statements primarily for polyglot code. -/
syntax stmtSeq := many1Indent(cStmtLike)

/--
A [`compound-statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements#Compound_statements
-/
syntax compStmt : cStmt := "{" cStmtLike* "}"

/-!
### Expression Statements

Collectively encode an [`expression-statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements#Expression_statements
-/

/-- A non-empty [`expression-statement`][1].

[1]: https://en.cppreference.com/w/c/language/statements#Expression_statements
-/
syntax exprStmt : cStmt := cExpr,+ endSemi

/-- A null statement. -/
syntax nullStmt : cStmt := ";"

/-!
### Iteration Statements

Collectively encode a [`iteration-statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements#Iteration_statements
-/

/-- A C [while](https://en.cppreference.com/w/c/language/while) loop. -/
syntax whileStmt : cStmt := "while " "(" cExpr,+ ")" cStmt

/-- A C [do-while](https://en.cppreference.com/w/c/language/do) loop. -/
syntax doWhileStmt : cStmt := "do " cStmt " while " "(" cExpr,+ ")"

/-- A C [for](https://en.cppreference.com/w/c/language/for) loop. -/
syntax forStmt := "for "
  "(" ((atomic(declaration) checkSemi) <|> (cExpr,* ";")) cExpr,* ";" cExpr,* ")" cStmt
attribute [cStmt_parser] forStmt

/-!
### Selection Statements

Collectively encode a [`selection-statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements#Selection_statements
-/

/-- A C [if](https://en.cppreference.com/w/c/language/if) statement. -/
syntax ifStmt : cStmt := "if " "(" cExpr,+ ")" cStmt (" else " cStmt)?

/-- A C [switch](https://en.cppreference.com/w/c/language/switch) statement. -/
syntax switchStmt : cStmt := &"switch " "(" cExpr,+ ")" cStmt

/-!
### Labeled Statements

Collectively encode a [`labeled-statement`][1] of the C grammar.

[1]: https://en.cppreference.com/w/c/language/statements#Labels
-/

/-- A target for a C goto statement. -/
syntax labelStmt : cStmt := ident ": " cStmt

/-- A case label in a C switch statement. -/
syntax caseStmt : cStmt := &"case " constExpr ": " cStmt

/-- A default label in a C switch statement. -/
syntax defaultStmt : cStmt := &"default" ": " cStmt

--------------------------------------------------------------------------------
/-! ## Top-Level Commands                                                     -/
--------------------------------------------------------------------------------

/-!
### External Declarations
-/

/-- An `external-declaration` of the C grammar. -/
declare_syntax_cat cExternDecl

/-- A [`function`](https://en.cppreference.com/w/c/language/functions) of the C grammar. -/
syntax function :=
  -- See `declaration` as to why the lookahead is needed.
  many1Lookahead(cDeclSpec, declarator) declarator declaration* compStmt

syntax function : cExternDecl
syntax declaration : cExternDecl

syntax cExternDecl : cCmd

--------------------------------------------------------------------------------
/-! ## Preprocessor Directives                                                -/
--------------------------------------------------------------------------------

/-!
### Headers
-/

/-- A `h-char-sequence` of the C grammar. -/
@[run_parser_attribute_hooks] def angleHeaderName :=
   raw (takeUntilFn fun c => c == '>')

syntax angleHeader := "<" angleHeaderName ">"

/-- A `header-name` of the C grammar. -/
syntax header := str <|> angleHeader

/-!
### Commands
-/

namespace PP

/-- A C preprocessor directive. -/
declare_syntax_cat ppCmd

syntax ppCmd : cCmd
syntax ppCmd : cStmt

/-- The C preprocessor null directive (does nothing). -/
syntax nullCmd : ppCmd := "#"

/-- [Include](https://en.cppreference.com/w/c/preprocessor/include) a C header. -/
syntax includeCmd : ppCmd := "#include " header

/-- Define a C [preprocessor macro](https://en.cppreference.com/w/cpp/preprocessor/replace). -/
syntax defineCmd : ppCmd :=
  "#define " rawIdent (noWs "("  rawIdent,*,?  "..."? ")")? line

/-- Remove a C [preprocessor macro](https://en.cppreference.com/w/cpp/preprocessor/replace). -/
syntax undefCmd : ppCmd := "#undef " rawIdent

/--
Change the [current line and file name][1] of the C preprocessor.

[1]: https://en.cppreference.com/w/c/preprocessor/line
-/
syntax lineCmd : ppCmd := "#line " line

/-- Cause a C preprocessor [error](https://en.cppreference.com/w/c/preprocessor/error). -/
syntax errorCmd : ppCmd := "#error " line

/--
Cause a C preprocessor [warning][1].
Standardized in C23, but provided by many compilers much earlier.

[1]: https://en.cppreference.com/w/c/preprocessor/error
-/
syntax warningCmd : ppCmd := "#warning " line

/-- Perform some [implementation-defined behavior](https://en.cppreference.com/w/c/preprocessor/impl). -/
syntax pragmaCmd : ppCmd := "#pragma " line

/-!
#### Conditional Inclusion

The preprocessor supports [conditional compilation][1] of parts of source file.
This behavior is controlled by the directives in this section.

[1]: https://en.cppreference.com/w/c/preprocessor/conditional
-/

/--
A C preprocessor `defined` unary expression.

This is made a `cExpr` to avoid duplicating much of the expression category
for preprocessor integral expressions.
-/
syntax:max "defined" (("(" ident ")") <|> ident) : cExpr

/--
The start of a C preprocessor conditional inclusion directive.

Process the following branch if the constant expression evaluates
to a nonzero integer.
-/
syntax ifCmd : ppCmd := "#if " constExpr

/--
The start of a C preprocessor conditional inclusion directive.

Process the following branch if the identifier is a defined macro.
-/
syntax ifdefCmd : ppCmd := "#ifdef " rawIdent

/--
An else-if branch of a C preprocessor conditional inclusion block.

Process the following branch if the identifier is *not* a defined macro.
-/
syntax ifndefCmd : ppCmd := "#ifndef " rawIdent

/--
An else-if branch of a C preprocessor conditional inclusion block.

Ends the previous branch of a conditional inclusion block and processes the
following branch if the constant expression evaluates to a nonzero integer.
-/
syntax elifCmd : ppCmd := "#elif " constExpr

/--
The else branch of a C preprocessor conditional inclusion block.

Ends the previous branch of a conditional inclusion block and processes
the following branch if the previous branch was skipped.
-/
syntax elseCmd : ppCmd := "#else"

/-- The end of a C preprocessor conditional inclusion block. -/
syntax endifCmd : ppCmd := "#endif"
