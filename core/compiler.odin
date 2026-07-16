package core

import "core:fmt"
import "core:strconv"

compile :: proc(source: string, chunk: ^Chunk, strings: ^Table) -> InterpretResult {
	scanner: Scanner
	scanner_init(&scanner, source)

	compiler: Compiler
	compiler_init(&compiler)

	parser: Parser
	parser_init(&parser, &scanner, &compiler, chunk, strings)

	advance(&parser)
	// expression(&parser)
	// consume(&parser, .EOF, "Expect end of expression.")

	for !match(&parser, .EOF) {
		declaration(&parser)
	}

	compiler_end(&parser)

	if parser.had_error {
		return .CompileError
	}

	return .Ok
}

UINT8_COUNT :: 255 + 1
Local :: struct {
	name:  Token,
	depth: int,
}

Compiler :: struct {
	locals:      [UINT8_COUNT]Local,
	local_count: int,
	scope_depth: int,
}

compiler_init :: proc(c: ^Compiler) {
	c.local_count = 0
	c.scope_depth = 0
}

@(private = "file")
begin_scope :: proc(p: ^Parser) {
	p.compiler.scope_depth += 1
}

@(private = "file")
end_scope :: proc(p: ^Parser) {
	c := p.compiler

	c.scope_depth -= 1

	for c.local_count > 0 && c.locals[c.local_count - 1].depth > c.scope_depth {
		emit_byte(p, .POP)
		c.local_count -= 1
	}
}

Precedence :: enum {
	NONE,
	ASSIGNMENT, // =
	OR, // or
	AND, // and
	EQUALITY, // == !=
	COMPARISON, // < > <= >=
	TERM, // + -
	FACTOR, // * /
	UNARY, // ! -
	CALL, // . ()
	PRIMARY,
}

@(private = "file")
next_precedence :: proc(prec: Precedence) -> Precedence {
	#partial switch prec {
	case .NONE:
		return .ASSIGNMENT
	case .ASSIGNMENT:
		return .OR
	case .OR:
		return .AND
	case .AND:
		return .EQUALITY
	case .EQUALITY:
		return .COMPARISON
	case .COMPARISON:
		return .TERM
	case .TERM:
		return .FACTOR
	case .FACTOR:
		return .UNARY
	case .UNARY:
		return .CALL
	case .CALL:
		return .PRIMARY
	case .PRIMARY:
		return .NONE
	}

	return .NONE
}

@(private = "file")
parse_precedence :: proc(p: ^Parser, precedence: Precedence) {
	advance(p)
	prefix_rule := get_rule(p.previous.type).prefix

	if prefix_rule == nil {
		error(p, "Expect expression.")
		return
	}

	can_assign := precedence <= .ASSIGNMENT
	prefix_rule(p, can_assign)

	for precedence <= get_rule(p.current.type).precedence {
		advance(p)
		infix_rule := get_rule(p.previous.type).infix
		infix_rule(p, can_assign)
	}

	if can_assign && match(p, .EQUAL) {
		error(p, "Invalid assignment target.")
	}
}

@(private = "file")
ParseFn :: proc(_: ^Parser, _: bool)


@(private = "file")
ParseRule :: struct {
	prefix:     ParseFn,
	infix:      ParseFn,
	precedence: Precedence,
}

@(private = "file")
get_rule :: proc(type: TokenType) -> ParseRule {
	#partial switch type {
	case .LEFT_PAREN:
		return ParseRule{grouping, nil, .NONE}
	case .MINUS:
		return ParseRule{unary, binary, .TERM}
	case .PLUS:
		return ParseRule{nil, binary, .TERM}
	case .SLASH:
		return ParseRule{nil, binary, .FACTOR}
	case .STAR:
		return ParseRule{nil, binary, .FACTOR}
	case .NUMBER:
		return ParseRule{number, nil, .NONE}
	case .FALSE, .TRUE, .NIL:
		return ParseRule{literal, nil, .NONE}
	case .BANG:
		return ParseRule{unary, nil, .NONE}
	case .BANG_EQUAL, .EQUAL_EQUAL:
		return ParseRule{nil, binary, .EQUALITY}
	case .GREATER, .GREATER_EQUAL, .LESS, .LESS_EQUAL:
		return ParseRule{nil, binary, .COMPARISON}
	case .STRING:
		return ParseRule{parse_string, nil, .NONE}
	case .IDENTIFIER:
		return ParseRule{variable, nil, .NONE}
	case .AND:
		return ParseRule{nil, and_, .AND}
	case .OR:
		return ParseRule{nil, or_, .OR}
	case:
		return ParseRule{nil, nil, .NONE}
	}

	unreachable()
}

Parser :: struct {
	current:    Token,
	previous:   Token,
	scanner:    ^Scanner,
	had_error:  bool,
	panic_mode: bool,
	chunk:      ^Chunk,
	strings:    ^Table,
	compiler:   ^Compiler,
}

parser_init :: proc(
	p: ^Parser,
	scanner: ^Scanner,
	compiler: ^Compiler,
	chunk: ^Chunk,
	strings: ^Table,
) {
	p.scanner = scanner
	p.compiler = compiler
	p.chunk = chunk
	p.strings = strings
	p.had_error = false
	p.panic_mode = false

}

@(private = "file")
advance :: proc(p: ^Parser) {
	p.previous = p.current

	for {
		p.current = scan_token(p.scanner)
		if p.current.type != .ERROR {break}

		error_at_current(p, p.current.error)
	}
}

@(private = "file")
error_at_current :: proc(p: ^Parser, message: string) {
	error_at(p, &p.current, message)
}

@(private = "file")
error :: proc(p: ^Parser, message: string) {
	error_at(p, &p.previous, message)
}

@(private = "file")
error_at :: proc(p: ^Parser, token: ^Token, message: string) {
	if p.panic_mode {return}
	p.panic_mode = true
	fmt.eprintf("[line %d] Error", token.line)

	if token.type == .EOF {
		fmt.eprint(" at end")
	} else if token.type == .ERROR {

	} else {
		fmt.eprintf(" at '%s'", p.scanner.source[token.start:token.start + token.length])
	}

	fmt.eprintfln(": %s", message)
	p.had_error = true
}


@(private = "file")
consume :: proc(p: ^Parser, type: TokenType, message: string) {
	if p.current.type == type {
		advance(p)
		return
	}

	error_at_current(p, message)
}

@(private = "file")
emit_byte :: proc(p: ^Parser, byte: OpCodeByte) {
	write_chunk(p.chunk, byte, p.previous.line)
}

@(private = "file")
emit_bytes :: proc(p: ^Parser, b1: OpCodeByte, b2: OpCodeByte) {
	emit_byte(p, b1)
	emit_byte(p, b2)
}


@(private = "file")
compiler_end :: proc(p: ^Parser) {
	emit_return(p)

	when ODIN_DEBUG {
		if !p.had_error {
			disassemble_chunk(p.chunk, "code")
		}
	}
}

@(private = "file")
emit_return :: proc(p: ^Parser) {
	emit_byte(p, OpCode.RETURN)
}

@(private = "file")
emit_constant :: proc(p: ^Parser, value: Value) {
	emit_bytes(p, OpCode.CONSTANT, make_constant(p, value))
}

@(private = "file")
make_constant :: proc(p: ^Parser, value: Value) -> byte {
	constant := add_constant(p.chunk, value)

	// UINT8_MAX
	if constant > 255 {
		error(p, "Too many constants in one chunk.")
		return 0
	}

	return u8(constant)
}

@(private = "file")
match :: proc(p: ^Parser, type: TokenType) -> bool {
	if !check(p, type) {return false}
	advance(p)
	return true
}

@(private = "file")
check :: proc(p: ^Parser, type: TokenType) -> bool {
	return p.current.type == type
}

@(private = "file")
synchronize :: proc(p: ^Parser) {
	p.panic_mode = false

	for p.current.type != .EOF {
		if p.previous.type == .SEMICOLON {return}

		#partial switch p.current.type {
		case .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN:
			return
		}

		advance(p)
	}
}

@(private = "file")
parse_variable :: proc(p: ^Parser, err: string) -> u8 {
	consume(p, .IDENTIFIER, err)

	declare_variable(p)
	if p.compiler.scope_depth > 0 {return 0}

	return identifier_constant(p, &p.previous)
}

@(private = "file")
identifier_constant :: proc(p: ^Parser, name: ^Token) -> u8 {
	return make_constant(
		p,
		cast(^Obj)obj_string_copy(
			p.scanner.source[name.start:name.start + name.length],
			p.strings,
			obj_allocated_cb,
		),
	)
}

@(private = "file")
define_variable :: proc(p: ^Parser, global: u8) {
	if p.compiler.scope_depth > 0 {
		mark_initialized(p.compiler)
		return
	}

	emit_bytes(p, OpCode.DEFINE_GLOBAL, global)
}

@(private = "file")
mark_initialized :: proc(c: ^Compiler) {
	c.locals[c.local_count - 1].depth = c.scope_depth
}

@(private = "file")
identifiers_equal :: proc(p: ^Parser, a: ^Token, b: ^Token) -> bool {
	a := p.scanner.source[a.start:a.start + a.length]
	b := p.scanner.source[b.start:b.start + b.length]

	return a == b
}

@(private = "file")
declare_variable :: proc(p: ^Parser) {
	if p.compiler.scope_depth == 0 {return}

	name := &p.previous

	for i := p.compiler.local_count - 1; i >= 0; i -= 1 {
		local := &p.compiler.locals[i]
		if local.depth != -1 && local.depth < p.compiler.scope_depth {
			break
		}

		if identifiers_equal(p, name, &local.name) {
			error(p, "Already a variable with this name in this scope.")
		}
	}

	add_local(p, name^)
}

@(private = "file")
add_local :: proc(p: ^Parser, name: Token) {
	if p.compiler.local_count == UINT8_COUNT {
		error(p, "Too many local variables in function.")
		return
	}

	local := &p.compiler.locals[p.compiler.local_count]
	p.compiler.local_count += 1

	local.name = name
	local.depth = -1
}

@(private = "file")
named_variable :: proc(p: ^Parser, name: Token, can_assign: bool) {
	name := name


	get_op, set_op: OpCode
	arg := resolve_local(p, &name)
	if (arg != -1) {
		get_op = .GET_LOCAL
		set_op = .SET_LOCAL
	} else {
		arg = cast(int)identifier_constant(p, &name)
		get_op = .GET_GLOBAL
		set_op = .SET_GLOBAL
	}

	if can_assign && match(p, .EQUAL) {
		expression(p)
		emit_bytes(p, set_op, u8(arg))
	} else {
		emit_bytes(p, get_op, u8(arg))
	}
}

@(private = "file")
resolve_local :: proc(p: ^Parser, name: ^Token) -> int {
	for i := p.compiler.local_count - 1; i >= 0; i -= 1 {
		local := &p.compiler.locals[i]
		if identifiers_equal(p, name, &local.name) {
			if local.depth == -1 {
				error(p, "Can't read local variables in its own initializer.")
			}
			return i
		}
	}

	return -1
}

@(private = "file")
emit_jump :: proc(p: ^Parser, instruction: OpCodeByte) -> int {
	emit_byte(p, instruction)
	emit_byte(p, 0xff)
	emit_byte(p, 0xff)
	return len(p.chunk.code) - 2
}

@(private = "file")
patch_jump :: proc(p: ^Parser, offset: int) {
	jump := len(p.chunk.code) - offset - 2

	u16_max := 65535
	if jump > u16_max {
		error(p, "Too much code to jump over.")
	}

	p.chunk.code[offset] = u8((jump >> 8) & 0xff)
	p.chunk.code[offset + 1] = u8(jump & 0xff)
}

@(private = "file")
emit_loop :: proc(p: ^Parser, loop_start: int) {
	emit_byte(p, .LOOP)

	offset := len(p.chunk.code) - loop_start + 2

	u16_max := 65535
	if offset > u16_max {error(p, "Loop body too large.")}

	emit_byte(p, (u8(offset) >> 8) & 0xff)
	emit_byte(p, u8(offset) & 0xff)
}

// PARSING FNS

@(private = "file")
number :: proc(p: ^Parser, _: bool) {
	src := p.scanner.source[p.previous.start:p.previous.start + p.previous.length]
	value, _ := strconv.parse_f64(src)
	emit_constant(p, value)
}

@(private = "file")
grouping :: proc(p: ^Parser, _: bool) {
	expression(p)
	consume(p, .RIGHT_PAREN, "Expect ')' after expression.")
}

@(private = "file")
unary :: proc(p: ^Parser, _: bool) {
	opType := p.previous.type

	parse_precedence(p, .UNARY)

	#partial switch opType {
	case .MINUS:
		emit_byte(p, OpCode.NEGATE)
	case .BANG:
		emit_byte(p, OpCode.NOT)
	case:
		unreachable()
	}
}

@(private = "file")
expression :: proc(p: ^Parser) {
	parse_precedence(p, .ASSIGNMENT)
}

@(private = "file")
binary :: proc(p: ^Parser, _: bool) {
	opType := p.previous.type
	rule := get_rule(opType)
	parse_precedence(p, next_precedence(rule.precedence))

	#partial switch opType {
	case .PLUS:
		emit_byte(p, .ADD)
	case .MINUS:
		emit_byte(p, .SUBTRACT)
	case .STAR:
		emit_byte(p, .MULTIPLY)
	case .SLASH:
		emit_byte(p, .DIVIDE)
	case .BANG_EQUAL:
		emit_bytes(p, .EQUAL, .NOT)
	case .EQUAL_EQUAL:
		emit_byte(p, .EQUAL)
	case .GREATER:
		emit_byte(p, .GREATER)
	case .GREATER_EQUAL:
		emit_bytes(p, .LESS, .NOT)
	case .LESS:
		emit_byte(p, .LESS)
	case .LESS_EQUAL:
		emit_bytes(p, .GREATER, .NOT)
	case:
		unreachable()
	}
}

@(private = "file")
literal :: proc(p: ^Parser, _: bool) {
	#partial switch p.previous.type {
	case .FALSE:
		emit_byte(p, OpCode.FALSE)
	case .TRUE:
		emit_byte(p, OpCode.TRUE)
	case .NIL:
		emit_byte(p, OpCode.NIL)
	case:
		unreachable()
	}
}


@(private = "file")
parse_string :: proc(p: ^Parser, _: bool) {
	emit_constant(
		p,
		cast(^Obj)obj_string_copy(
			p.scanner.source[p.previous.start + 1:p.previous.start + p.previous.length - 1],
			p.strings,
			obj_allocated_cb,
		),
	)
}

@(private = "file")
declaration :: proc(p: ^Parser) {
	if match(p, .VAR) {
		var_declaration(p)
	} else {
		statement(p)
	}

	if p.panic_mode {synchronize(p)}
}

@(private = "file")
statement :: proc(p: ^Parser) {
	if match(p, .PRINT) {
		print_statement(p)
	} else if match(p, .FOR) {
		for_statement(p)
	} else if match(p, .IF) {
		if_statement(p)
	} else if match(p, .WHILE) {
		while_statement(p)
	} else if match(p, .LEFT_BRACE) {
		begin_scope(p)
		block(p)
		end_scope(p)
	} else {
		expression_statement(p)
	}
}

@(private = "file")
print_statement :: proc(p: ^Parser) {
	expression(p)
	consume(p, .SEMICOLON, "Expect ';' after value.")
	emit_byte(p, OpCode.PRINT)
}

@(private = "file")
expression_statement :: proc(p: ^Parser) {
	expression(p)
	consume(p, .SEMICOLON, "Expect ';' after expression.")
	emit_byte(p, OpCode.POP)
}

@(private = "file")
var_declaration :: proc(p: ^Parser) {
	global := parse_variable(p, "Expect variable name")

	if match(p, .EQUAL) {
		expression(p)
	} else {
		emit_byte(p, OpCode.NIL)
	}
	consume(p, .SEMICOLON, "Expect ';' after variable declaration")

	define_variable(p, global)
}

@(private = "file")
variable :: proc(p: ^Parser, can_assign: bool) {
	named_variable(p, p.previous, can_assign)
}

@(private = "file")
block :: proc(p: ^Parser) {
	for !check(p, .RIGHT_BRACE) && !check(p, .EOF) {
		declaration(p)
	}

	consume(p, .RIGHT_BRACE, "Expect '}' after block.")
}


@(private = "file")
if_statement :: proc(p: ^Parser) {
	consume(p, .LEFT_PAREN, "Expect '(' after 'if'.")
	expression(p)
	consume(p, .RIGHT_PAREN, "Expect ')' after condition.")

	then_jmp := emit_jump(p, OpCode.JUMP_IF_FALSE)
	emit_byte(p, .POP)
	statement(p)

	else_jump := emit_jump(p, OpCode.JUMP)

	patch_jump(p, then_jmp)
	emit_byte(p, .POP)

	if match(p, .ELSE) {statement(p)}
	patch_jump(p, else_jump)
}

@(private = "file")
and_ :: proc(p: ^Parser, _can_assign: bool) {
	end_jump := emit_jump(p, .JUMP_IF_FALSE)

	emit_byte(p, .POP)
	parse_precedence(p, .AND)

	patch_jump(p, end_jump)
}

@(private = "file")
or_ :: proc(p: ^Parser, _can_assign: bool) {
	else_jump := emit_jump(p, .JUMP_IF_FALSE)
	end_jump := emit_jump(p, .JUMP)

	patch_jump(p, else_jump)
	emit_byte(p, .POP)

	parse_precedence(p, .OR)
	patch_jump(p, end_jump)
}

@(private = "file")
while_statement :: proc(p: ^Parser) {
	loop_start := len(p.chunk.code)

	consume(p, .LEFT_PAREN, "Expect '(' after 'while'.")
	expression(p)
	consume(p, .RIGHT_PAREN, "Expect ')' after condition.")

	exit_jump := emit_jump(p, .JUMP_IF_FALSE)
	emit_byte(p, .POP)
	statement(p)
	emit_loop(p, loop_start)

	patch_jump(p, exit_jump)
	emit_byte(p, .POP)
}

@(private = "file")
for_statement :: proc(p: ^Parser) {
	begin_scope(p)
	consume(p, .LEFT_PAREN, "Expect '(' after 'for'.")

	if match(p, .SEMICOLON) {
		//No init
	} else if match(p, .VAR) {
		var_declaration(p)
	} else {
		expression_statement(p)
	}

	loop_start := len(p.chunk.code)
	exit_jump := -1

	if !match(p, .SEMICOLON) {
		expression(p)
		consume(p, .SEMICOLON, "Expect ';' after loop condition.")

		// Jump out if condition is false
		exit_jump = emit_jump(p, .JUMP_IF_FALSE)
		emit_byte(p, .POP)
	}

	if !match(p, .RIGHT_PAREN) {
		body_jump := emit_jump(p, .JUMP)
		increment_start := len(p.chunk.code)
		expression(p)
		emit_byte(p, .POP)
		consume(p, .RIGHT_PAREN, "Expect ')' after for clauses.")

		emit_loop(p, loop_start)
		loop_start = increment_start
		patch_jump(p, body_jump)
	}

	statement(p)
	emit_loop(p, loop_start)

	if exit_jump != -1 {
		patch_jump(p, exit_jump)
		emit_byte(p, .POP)
	}

	end_scope(p)
}

