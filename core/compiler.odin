package core

import "core:fmt"
import "core:strconv"

compile :: proc(source: string, chunk: ^Chunk, strings: ^Table) -> InterpretResult {
	scanner: Scanner
	scanner_init(&scanner, source)

	parser: Parser
	parser_init(&parser, &scanner, chunk, strings)

	advance(&parser)
	expression(&parser)
	consume(&parser, .EOF, "Expect end of expression.")

	compiler_end(&parser)

	if parser.had_error {
		return .CompileError
	}

	return .Ok
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

	prefix_rule(p)

	for precedence <= get_rule(p.current.type).precedence {
		advance(p)
		infix_rule := get_rule(p.previous.type).infix
		infix_rule(p)
	}
}

@(private = "file")
ParseFn :: proc(_: ^Parser)

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
}

parser_init :: proc(p: ^Parser, s: ^Scanner, c: ^Chunk, strings: ^Table) {
	p.scanner = s
	p.had_error = false
	p.panic_mode = false
	p.chunk = c
	p.strings = strings
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
number :: proc(p: ^Parser) {
	src := p.scanner.source[p.previous.start:p.previous.start + p.previous.length]
	value, _ := strconv.parse_f64(src)
	emit_constant(p, value)
}

@(private = "file")
grouping :: proc(p: ^Parser) {
	expression(p)
	consume(p, .RIGHT_PAREN, "Expect ')' after expression.")
}

@(private = "file")
unary :: proc(p: ^Parser) {
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
binary :: proc(p: ^Parser) {
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
literal :: proc(p: ^Parser) {
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
parse_string :: proc(p: ^Parser) {
	emit_constant(
		p,
		cast(^Obj)obj_string_copy(
			p.scanner.source[p.previous.start + 1:p.previous.start + p.previous.length - 1],
			p.strings,
			obj_allocated_cb,
		),
	)
}

