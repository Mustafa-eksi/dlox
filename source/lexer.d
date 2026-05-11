/// A simple Lexer implementation

import std.conv : to;
import std.ascii : isWhite;

/++
 + Lexer struct is a really customizable lexer.
 +
 + Params:
 +      T = Token enumeration type that is convertable to integer. There must be
 +          a epsilon token that has the 0 value.
 +
 + Example:
 + ---d
 + enum Tokens {
 +     Epsilon = 0
 +     Identifier,
 +     OpenParen,
 +     CloseParen,
 + }
 + Tokens tokenizer(string lex) {
 +     if (lex == "(")
 +         return Tokens.OpenParen;
 +     else if (lex == ")")
 +         return Tokens.CloseParen;
 +     return Tokens.Identifier;
 + }
 + string source_code = "abc ((def) ghi)";
 + // We use an alias for conciseness.
 + alias MyLexer = Lexer!Tokens;
 + auto lexer = Lexer!Tokens(source_code, &tokenizer);
 + MyLexer.Token tk = lexer.next_symbol();
 + while (tk.type != Tokens.Epsilon) {
 +     // Do what ever you want to the token
 +     tk = lexer.next_symbol();
 + }
 + ---
 +/
struct Lexer(T: int) {
    /// Internal token type for packaging semantic information with the token
    struct Token {
        T type;
        /// String slice from the source code of the token
        string seminfo;
    }

    string source_code;
    size_t cursor;
    T function(string lex) tokenizer;
    bool[char] separators;
    bool[char] discarding_separators;

    /**
     * This constructor uses default separator and discarding_separator
     * associative arrays.
     *
     * Params:
     *      src = Source code you want to lex.
     *      tz = Tokenizer function that takes lexemes and returns Tokens.
     */
    this (string src, T function(string lex) tz) {
        source_code = src;
        cursor = 0;
        separators = [';': true, ',': true, '\'': true, '*': true, '(': true,
                   ')': true, '{': true, '}': true];
        discarding_separators = [' ': true, '\n': true];
        tokenizer = tz;
    }

    /**
     * This is the more general form of the previous constructor.
     * 
     * Params:
     *      src = Source code you want to lex.
     *      sp = Associative array of separators. Separators should be set to
     *      true.
     *      ds = Same as sp but these get discarded, useful for discarding
     *      whitespace.
     *      tz = Tokenizer function that takes lexemes and returns Tokens.
     */
    this (string src, bool[char] sp, bool[char] ds, T function(string lex) tz) {
        source_code = src;
        cursor = 0;
        separators = sp;
        discarding_separators = ds;
        tokenizer = tz;
    }

    /// Returns next symbol, advances cursor. Returns Epsilon (0) on file end.
    Token next_symbol() {
        // TODO: change isWhite with separators and discarding separators
        while (cursor < source_code.length && source_code[cursor] in
                discarding_separators) {
            cursor++;
        }
        size_t start = cursor;
        if (cursor >= source_code.length)
            return Token(to!T(0), "");
        while (cursor < source_code.length && source_code[cursor] !in separators
                && source_code[cursor] !in discarding_separators) {
            cursor++;
        }
        if (source_code[cursor] in separators && start == cursor) {
            cursor++;
        }
        auto ty = tokenizer(source_code[start..cursor]);
        return Token(ty, source_code[start..cursor]);
    }
}

