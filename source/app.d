import std.stdio : writeln;
import std.file : exists, read;
import std.conv : to;
import lexer;
import parser;

enum Tokens : int {
    EOF = 0,
    IDENTIFIER,
    COMMA,
    SEMICOLON,
    OPAREN,
    CPAREN,
    OCURLY,
    CCURLY,
}

const Tokens[string] LEXEME_TABLE = [
    ",": Tokens.COMMA,
    ";": Tokens.SEMICOLON,
    "(": Tokens.OPAREN,
    ")": Tokens.CPAREN,
    "{": Tokens.OCURLY,
    "}": Tokens.CCURLY,
];

Tokens tokenizer(string lex) {
    if (lex in LEXEME_TABLE)
        return LEXEME_TABLE[lex];
    return Tokens.IDENTIFIER;
}

int main(string[] args)
{
    if (args.length < 2) {
        writeln("USAGE: ./dlox <filename>");
        return -1;
    }
    string source_filename = args[1];
    if (!exists(source_filename)) {
        writeln("Error: Can't access file");
        return -1;
    }
    string source_code = to!string(read(source_filename));
    auto lexer = Lexer!Tokens(source_code, &tokenizer);
    auto tk = lexer.next_symbol();
    while (tk.type != Tokens.EOF) {
        writeln(tk);
        tk = lexer.next_symbol();
    }
    return 0;
}
