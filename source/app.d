import std.stdio : writeln;
import std.file : exists, read;
import std.conv : to;
import std.typecons : tuple;
import lexer;
import parser;

enum Tokens {
    EPSILON = 0,
    IDENTIFIER = 1,
    COMMA,
    SEMICOLON,
    OPAREN,
    CPAREN,
    OCURLY,
    CCURLY,
    PLUS,
    TIMES,
}

enum Nonterminals {
    Unknown = 0,
    Expression,
    ExpressionRest,
    Term,
    TermRest,
    Factor,
}

const Tokens[string] LEXEME_TABLE = [
    ",": Tokens.COMMA,
    ";": Tokens.SEMICOLON,
    "(": Tokens.OPAREN,
    ")": Tokens.CPAREN,
    "{": Tokens.OCURLY,
    "}": Tokens.CCURLY,
    "+": Tokens.PLUS,
    "*": Tokens.TIMES,
];

alias GS = Parser!(Tokens, Nonterminals).GrammarSymbol;


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
    Tokens[] tokens;
    while (tk.type != Tokens.EPSILON) {
        writeln(tk);
        tokens ~= tk.type;
        tk = lexer.next_symbol();
    }
    /*
     * E    = TE'
     * E'   = +TE' | e
     * T    = FT'
     * T'   = *FT' | e
     * F    = (E) | id
     */
    /*
    GS[][NonTerminals] first_table = [
        Factor: [OPAREN, IDENTIFIER],
        TermRest: [TIMES],
        Term: [OPAREN, IDENTIFIER],
        ExpressionRest: [PLUS],
        Expression: [OPAREN, IDENTIFIER]
    ];
    */
    GS[][][Nonterminals] RULE_SET = [
        Nonterminals.Expression: [
            [
                GS(Nonterminals.Term), GS(Nonterminals.ExpressionRest),
            ]
        ],
        Nonterminals.ExpressionRest: [
            [
                GS(Tokens.PLUS), GS(Nonterminals.Term),
                GS(Nonterminals.ExpressionRest)
            ],
            []
        ],
        Nonterminals.Term: [[GS(Nonterminals.Factor), GS(Nonterminals.TermRest)]],
        Nonterminals.TermRest: [
            [GS(Tokens.TIMES), GS(Nonterminals.Factor), GS(Nonterminals.TermRest)],
            []
        ],
        Nonterminals.Factor: [
            [GS(Tokens.OPAREN), GS(Nonterminals.Expression), GS(Tokens.CPAREN)],
            [GS(Tokens.IDENTIFIER)]
        ],
    ];
    auto parser = Parser!(Tokens, Nonterminals)(tokens, RULE_SET,
        Nonterminals.Expression);
    writeln(parser.first_table);
    writeln();
    writeln(parser.follow_table);
    return 0;
}
