package core

TokenType :: enum {
	// Single-character tokens.
	LEFT_PAREN,
	RIGHT_PAREN,
	LEFT_BRACE,
	RIGHT_BRACE,
	COMMA,
	DOT,
	MINUS,
	PLUS,
	SEMICOLON,
	SLASH,
	STAR,
	// One or two character tokens.
	BANG,
	BANG_EQUAL,
	EQUAL,
	EQUAL_EQUAL,
	GREATER,
	GREATER_EQUAL,
	LESS,
	LESS_EQUAL,
	// Literals.
	IDENTIFIER,
	STRING,
	NUMBER,
	// Keywords.
	AND,
	CLASS,
	ELSE,
	FALSE,
	FOR,
	FUN,
	IF,
	NIL,
	OR,
	PRINT,
	RETURN,
	SUPER,
	THIS,
	TRUE,
	VAR,
	WHILE,
	ERROR,
	EOF,
}

Token :: struct {
	type:   TokenType,
	start:  int,
	length: int,
	line:   int,
	error:  string,
}

Scanner :: struct {
	start:   int,
	current: int,
	line:    int,
	source:  string,
}

scanner_init :: proc(s: ^Scanner, source: string) {
	s.start = 0
	s.current = 0
	s.line = 1
	s.source = source

	a := source[1]
}


scan_token :: proc(s: ^Scanner) -> Token {
	skip_whitespace(s)

	s.start = s.current

	if is_at_end(s) {
		return make_token(s, .EOF)
	}

	c := advance(s)

	if is_alpha(c) {
		return scan_identifier(s)
	}
	if is_digit(c) {
		return scan_number(s)
	}

	switch c {
	case '(':
		return make_token(s, .LEFT_PAREN)
	case ')':
		return make_token(s, .RIGHT_PAREN)
	case '{':
		return make_token(s, .LEFT_BRACE)
	case '}':
		return make_token(s, .RIGHT_BRACE)
	case ';':
		return make_token(s, .SEMICOLON)
	case ',':
		return make_token(s, .COMMA)
	case '.':
		return make_token(s, .DOT)
	case '-':
		return make_token(s, .MINUS)
	case '+':
		return make_token(s, .PLUS)
	case '/':
		return make_token(s, .SLASH)
	case '*':
		return make_token(s, .STAR)
	case '!':
		return make_token(s, match(s, '=') ? .BANG_EQUAL : .BANG)
	case '=':
		return make_token(s, match(s, '=') ? .EQUAL_EQUAL : .EQUAL)
	case '<':
		return make_token(s, match(s, '=') ? .LESS_EQUAL : .LESS)
	case '>':
		return make_token(s, match(s, '=') ? .GREATER_EQUAL : .GREATER)
	case '"':
		return scan_string(s)
	}

	return error_token(s, "Unexpected character")
}

@(private = "file")
is_at_end :: proc(s: ^Scanner) -> bool {
	return s.current >= len(s.source)
}

@(private = "file")
make_token :: proc(s: ^Scanner, type: TokenType) -> Token {
	return Token {
		type = type,
		start = s.start,
		length = s.current - s.start,
		line = s.line,
		error = "",
	}
}


@(private = "file")
error_token :: proc(s: ^Scanner, message: string) -> Token {
	return Token {
		type = .ERROR,
		start = s.start,
		length = s.current - s.start,
		line = s.line,
		error = message,
	}
}

@(private = "file")
advance :: proc(s: ^Scanner) -> rune {
	s.current += 1
	return rune(s.source[s.current - 1])
}


@(private = "file")
match :: proc(s: ^Scanner, expected: u8) -> bool {
	if is_at_end(s) {return false}

	if (s.source[s.current] != expected) {return false}

	s.current += 1
	return true
}


@(private = "file")
skip_whitespace :: proc(s: ^Scanner) {
	for {
		c := peek(s)

		switch c {
		case ' ':
			fallthrough
		case '\r':
			fallthrough
		case '\t':
			advance(s)
		case '\n':
			s.line += 1
			advance(s)
		case '/':
			if peek_next(s) == '/' {
				// Skip comment til the end of the line
				for peek(s) != '\n' && !is_at_end(s) {
					advance(s)
				}
			} else {
				return
			}
		case:
			return
		}
	}
}

@(private = "file")
peek :: proc(s: ^Scanner) -> rune {
	if is_at_end(s) {return cast(rune)0}
	return rune(s.source[s.current])
}

@(private = "file")
peek_next :: proc(s: ^Scanner) -> Maybe(rune) {
	if is_at_end(s) {return nil}
	if s.current + 1 >= len(s.source) {return nil}
	return rune(s.source[s.current + 1])
}


@(private = "file")
scan_string :: proc(s: ^Scanner) -> Token {
	for peek(s) != '"' && !is_at_end(s) {
		if peek(s) == '\n' {s.line += 1}
		advance(s)
	}

	if is_at_end(s) {return error_token(s, "Unterminated string")}

	advance(s)
	return make_token(s, .STRING)
}

@(private = "file")
is_digit :: proc(c: rune) -> bool {
	return c >= '0' && c <= '9'
}

@(private = "file")
is_alpha :: proc(c: rune) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'}


@(private = "file")
scan_number :: proc(s: ^Scanner) -> Token {
	for is_digit(peek(s)) {
		advance(s)
	}

	next, ok := peek_next(s).?
	if peek(s) == '.' && ok && is_digit(next) {
		advance(s)

		for is_digit(peek(s)) {advance(s)}
	}

	return make_token(s, .NUMBER)
}

@(private = "file")
scan_identifier :: proc(s: ^Scanner) -> Token {
	for is_alpha(peek(s)) || is_digit(peek(s)) {advance(s)}

	return make_token(s, identifier_type(s))
}


@(private = "file")
identifier_type :: proc(s: ^Scanner) -> TokenType {
	switch s.source[s.start] {
	case 'a':
		return check_keyword(s, 1, 2, "nd", .AND)
	case 'c':
		return check_keyword(s, 1, 4, "lass", .CLASS)
	case 'e':
		return check_keyword(s, 1, 3, "lse", .ELSE)
	case 'f':
		if s.current - s.start > 1 {
			switch s.source[s.start + 1] {
			case 'a':
				return check_keyword(s, 2, 3, "lse", .FALSE)
			case 'o':
				return check_keyword(s, 2, 1, "r", .FOR)
			case 'u':
				return check_keyword(s, 2, 1, "n", .FUN)
			}
		}
	case 'i':
		return check_keyword(s, 1, 1, "f", .IF)
	case 'n':
		return check_keyword(s, 1, 2, "il", .NIL)
	case 'o':
		return check_keyword(s, 1, 1, "r", .OR)
	case 'p':
		return check_keyword(s, 1, 4, "rint", .PRINT)
	case 'r':
		return check_keyword(s, 1, 5, "eturn", .RETURN)
	case 's':
		return check_keyword(s, 1, 4, "uper", .SUPER)
	case 't':
		if s.current - s.start > 1 {
			switch s.source[s.start + 1] {
			case 'h':
				return check_keyword(s, 2, 2, "is", .THIS)
			case 'r':
				return check_keyword(s, 2, 2, "ue", .TRUE)
			}
		}
	case 'v':
		return check_keyword(s, 1, 2, "ar", .VAR)
	case 'w':
		return check_keyword(s, 1, 4, "hile", .WHILE)
	}

	return .IDENTIFIER
}

@(private = "file")
check_keyword :: proc(
	s: ^Scanner,
	start: int,
	length: int,
	rest: string,
	type: TokenType,
) -> TokenType {
	total_len := start + length

	if s.current - s.start == total_len {
		if s.source[s.start + start:s.start + total_len] == rest {
			return type
		}
	}

	return .IDENTIFIER
}

