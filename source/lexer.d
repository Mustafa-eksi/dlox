import std.conv : to;
import std.ascii : isWhite;

struct Lexer(T: int) {
    struct Token {
        T type;
        // seminfo => Semantic Information.
        // String slice from the source code of the token
        string seminfo;
    }
    string source_code;
    size_t cursor;
    T function(string lex) tokenizer;
    bool[char] separators;
    bool[char] discarding_separators;

    this (string src, T function(string lex) tz) {
        source_code = src;
        cursor = 0;
        separators = [';': true, ',': true, '\'': true, '*': true, '(': true,
                   ')': true, '{': true, '}': true];
        discarding_separators = [' ': true, '\n': true];
        tokenizer = tz;
    }

    this (string src, bool[char] sp, bool[char] ds, T function(string lex) tz) {
        source_code = src;
        cursor = 0;
        separators = sp;
        discarding_separators = ds;
        tokenizer = tz;
    }

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

