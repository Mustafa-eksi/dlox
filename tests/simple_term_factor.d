import std.stdio : writeln, write;
import std.file : exists, read;
import std.conv : to, parse;
import std.typecons : tuple;
import std.sumtype : has, get;
import dlox;

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

bool[char] SEPARATORS = [
    ',': true, ';': true, '(': true, ')': true, '{': true, '}': true, '+': true,
    '*':true,
];
bool[char] DISCARDING_SEPARATORS = ['\n': true, ' ': true];

alias GS = Parser!(Tokens, Nonterminals).GrammarSymbol;
alias GT = Parser!(Tokens, Nonterminals).GrammarTable;
alias CNode = Parser!(Tokens, Nonterminals).CNode;
alias Token = Lexer!Tokens.Token;

Tokens tokenizer(string lex) {
    if (lex in LEXEME_TABLE)
        return LEXEME_TABLE[lex];
    return Tokens.IDENTIFIER;
}

float interpret(CNode *node) {
    if (node.type.has!Nonterminals) {
        switch (node.type.get!Nonterminals) {
        case Nonterminals.Expression:
            return interpret(node.children[1]) + interpret(node.children[0]);
        case Nonterminals.ExpressionRest:
            if (node.alt_idx == 0)
                return interpret(node.children[0]) +
                    interpret(node.children[1]);
            else
                return 0;
        case Nonterminals.Term:
            return interpret(node.children[1])*interpret(node.children[0]);
        case Nonterminals.TermRest:
            if (node.alt_idx == 0)
                return interpret(node.children[0]) *
                    interpret(node.children[1]);
            else
                return 1;
        case Nonterminals.Factor:
            if (node.alt_idx == 0)
                return interpret(node.children[1]);
            else
                return interpret(node.children[0]);
        default: assert(0);
        }
    } else {
        auto t = node.type.get!Token;
        assert(t.type == Tokens.IDENTIFIER, "Error: can not interpret non-identifier");
        return node.type.get!Token.seminfo.parse!float;
    }
}

int main(string[] args)
{
    if (args.length < 2) {
        writeln("USAGE: ./dlox <filename> | <command> | -h");
        return -1;
    }
    if (args[1] == "-h") {
        writeln("USAGE: ./dlox <filename> | <command> | -h");
        writeln("Commands:");
        writeln("\tdump_grammar");
        writeln("\tprint_parsing_table");
        writeln("\tprint_first_table");
        writeln("\tprint_follow_table");
        writeln("\tdump_cst (specify filename in next argument)");
        writeln("\tdump_tokens (specify filename in next argument)");
        return 0;
    }
    string source_filename;
    if (args[1] == "dump_cst" || args[1] == "dump_tokens")
        source_filename = args[2];
    else
        source_filename = args[1];

    GT RULE_SET = [
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

    auto parser = Parser!(Tokens, Nonterminals)(RULE_SET, Nonterminals.Expression);
    if (args[1] == "dump_grammar") {
        writeln(RULE_SET);
        return 0;
    } else if (args[1] == "print_first_table") {
        foreach (nt, alt; parser.first_table) {
            write(nt.to!Nonterminals, ": [");
            foreach (tok, alt_idx; alt) {
                if (alt_idx == -1) continue;
                write(tok.to!Tokens, ": ", alt_idx,", ");
            }
            writeln("],");
        }
        return 0;
    } else if (args[1] == "print_follow_table") {
        foreach (nt, alt; parser.follow_table) {
            write(nt.to!Nonterminals, ": [");
            foreach (tok, alt_idx; alt) {
                if (alt_idx == -1) continue;
                write(tok.to!Tokens, ": ", alt_idx,", ");
            }
            writeln("],");
        }
        return 0;
    } else if (args[1] == "print_parsing_table") {
        writeln(parser.parsing_table);
        foreach (nt, alt; parser.parsing_table) {
            write(nt.to!Nonterminals, ": [");
            foreach (tok, alt_idx; alt) {
                if (alt_idx == -1) continue;
                write(tok.to!Tokens, ": ", alt_idx,", ");
            }
            writeln("],");
        }
        return 0;
    }
    if (!exists(source_filename)) {
        writeln("Error: Can't access file");
        return -1;
    }

    string source_code = to!string(read(source_filename));
    auto lexer = Lexer!Tokens(source_code, SEPARATORS, DISCARDING_SEPARATORS, &tokenizer);
    auto tk = lexer.next_symbol();
    Token[] tokens;
    while (tk.type != Tokens.EPSILON) {
        // writeln(tk);
        tokens ~= tk;
        tk = lexer.next_symbol();
    }
    if (args[1] == "dump_tokens") {
        writeln(tokens);
    }

    /*
     * E    = TE'
     * E'   = +TE' | e
     * T    = FT'
     * T'   = *FT' | e
     * F    = (E) | id
     */

    tokens ~= Token(Tokens.EPSILON, "");
    auto tree = parser.parse(tokens);
    if (args[1] == "dump_cst") {
        tree.print();
    } else {
        writeln(interpret(&tree));
    }
    return 0;
}
