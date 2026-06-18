/// A simple Lexer implementation
module dlox.lexer;

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
 + ---
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
    struct LexerToken {
        /// Token type, should be from the token enumeration T
        T type;
        /// String slice from the source code of the token
        string seminfo;
    }

    /// Source code to lex.
    string source_code;

    /// Cursor for the current position in the source code.
    size_t cursor;

    /// Tokenizer function that takes lexemes and returns Tokens.
    T function(string lex) tokenizer;

    /// Associative array of separators. Separators should be set to true.
    bool[char] separators;

    /// Same as separators but these get discarded, useful for discarding
    /// whitespace.
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
                   ')': true, '{': true, '}': true, '+': true];
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

    /++
     + Advances to next symbol.
     + Returns: Next token, advances cursor. Returns Epsilon (0) on file end.
     +/
    LexerToken next_symbol() {
        // TODO: change isWhite with separators and discarding separators
        while (cursor < source_code.length && source_code[cursor] in
                discarding_separators) {
            cursor++;
        }
        size_t start = cursor;
        if (cursor >= source_code.length)
            return LexerToken(to!T(0), "");
        while (cursor < source_code.length && source_code[cursor] !in separators
                && source_code[cursor] !in discarding_separators) {
            cursor++;
        }
        if (cursor < source_code.length && source_code[cursor] in separators && start == cursor)
        {
            cursor++;
        }
        auto ty = tokenizer(source_code[start..cursor]);
        return LexerToken(ty, source_code[start..cursor]);
    }
}

/// Tokenizer function for unit tests.
T __unittest_tokenizer(T)(string lex) {
    import std.range : empty;
    if (lex == "+")
        return T.Plus;
    else if (lex.empty)
        return T.Epsilon;
    else
        return T.Identifier;
}

///
unittest {
    enum Tokens {
        Epsilon = 0,
        Identifier,
        Plus,
    }
    alias mLexer = Lexer!Tokens;
    string source = "10 + 15 + 20";
    mLexer lexer = mLexer(source, &__unittest_tokenizer!Tokens);
    Tokens[] tokens;
    auto tk = lexer.next_symbol();
    while (tk.type != Tokens.Epsilon) {
        tokens ~= tk.type;
        tk = lexer.next_symbol();
    }
    assert(tokens == [
            Tokens.Identifier, Tokens.Plus, Tokens.Identifier, Tokens.Plus,
            Tokens.Identifier
        ]);
}

unittest {
    import std.random : uniform;
    import std.conv : to;
    import std.stdio : writeln;

    enum Tokens {
        Epsilon = 0,
        Identifier,
        Plus,
    }
    alias mLexer = Lexer!Tokens;
    string generateIdentifier() {
        const ulong length = uniform(1, 10);
        string output;
        for (int i = 0; i < length; i++) {
            output ~= uniform('a', 'z'+1);
        }
        return output;
    }
    Tokens[] generateRandomTokens() {
        const ulong length = uniform(10, 15);
        Tokens[] output;
        for (int i = 0; i < length; i++) {
            // FIXME: get first and last instead of hardcoding
            output ~= uniform(Tokens.Identifier, Tokens.Plus+1).to!Tokens;
        }
        return output;
    }
    string generateSource(Tokens[] tokens) {
        string output;
        ulong space_count = uniform(0, 20);
        for (int si = 0; si < space_count; si++)
            output ~= ' ';
        foreach (tok; tokens) {
            if (tok == Tokens.Identifier) {
                output ~= generateIdentifier();
                space_count = uniform(1, 20);
            } else if (tok == Tokens.Plus) {
                output ~= '+';
                space_count = uniform(0, 20);
            } else {
                assert(false);
            }
            for (int si = 0; si < space_count; si++)
                output ~= ' ';
        }
        return output;
    }
    for (int fuzz = 0; fuzz < 100; fuzz++) {
        Tokens[] expected = generateRandomTokens();
        string source = generateSource(expected);
        mLexer lexer = mLexer(source, &__unittest_tokenizer!Tokens);
        auto tk = lexer.next_symbol();
        ulong i = 0;
        while (tk.type != Tokens.Epsilon) {
            if (tk.type != expected[i]) {
                writeln("Source Code: '", source, "'");
                writeln("Source Cursor: ", lexer.cursor);
                writeln("Expected: ", expected[i]);
                writeln("Found: ", tk.type);
                writeln("Expected Array: ", expected);
                assert(false);
            }
            tk = lexer.next_symbol();
            i++;
        }
    }
}
