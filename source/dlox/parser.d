/// Predictive Parser Implementation
module dlox.parser;

import std.sumtype : SumType, match, has, get;
import std.typecons : Tuple, tuple;
import std.conv : to;
import std.range : empty, back, front, chain;
import std.algorithm.mutation : stripRight, remove;
import std.algorithm.searching : canFind;
import std.array : assocArray, byPair, popBack;
import std.stdio : writeln, writefln;

import dlox.cst;
import dlox.lexer;

/* TODO:
 * 1- Left recursion elimination
 * 2- Left factoring (for predictive parsing)
 *      - When left factored most grammars are LL(1)
 * 3- Check if the grammar is LL(1)
 */

/++
 + Parser template creates a LL(1) parser for the given grammar and
 + tokens.
 +
 + Params:
 +     T = Token enumeration type. T should has 0 reserved as EOF/EPSILON.
 +         Naming doesn't matter but don't use 0 for different things.
 +     N = Nonterminal enumeration type
 +/
struct Parser(T, N) {
    const T epsilon = cast(T)0;
    alias TokenInfo = Lexer!T.Token;
    alias GrammarSymbol = SumType!(T, N);
    alias GrammarTable = GrammarSymbol[][][N];
    GrammarTable rule_list;

    N start_nt;

    alias RuleIndex = Tuple!(int, N);
    int[T][N] parsing_table;

    int[T][N] first_table;
    int[T][N] follow_table;

    /++
     + Gets first set of the given rule.
     +
     + Params:
     +      nt = Nonterminal of the rule
     +      alt_idx = Which alternative to get first of.
     + Returns: First set of the given rule.
     +/
    int[T] getFirst(N nt, int alt_idx) {
        int[T] output;
        if (rule_list[nt][alt_idx].empty) {
            output[epsilon] = alt_idx;
            return output;
        }

        auto f = rule_list[nt][alt_idx].front;
        if (f.has!T) {
            output[f.get!T] = alt_idx;
        } else { // f is a nonterminal
            // For each alternative f has we call getFirst function recursively
            // and add it to our output.
            foreach (f_alt, _; rule_list[f.get!N]) {
                auto ff = getFirst(f.get!N, f_alt.to!int);
                output = chain(output.byPair, ff.byPair).assocArray;
            }
            // Since output is from getFirst, their values will be the
            // alternative indices of f. We have to set them all to alt_idx.
            foreach (tok, ref alt; output) {
                alt = alt_idx;
            }
        }
        return output;
    }

    /++
     + Initializers "First" sets of each nonterminal.
     +
     + First set of a nonterminal includes every token that can be the leftmost
     + symbol of that nonterminal.
     + Example: For this production
     + A = xyz | bcde | efg
     + First(A) = {x, b, e}
     +/
    void initFirst() {
        // This iterates every production
        foreach (nt, rule; rule_list) {
            foreach (alt_idx, _; rule) {
                // Calls the recursive function
                auto f = getFirst(nt, alt_idx.to!int);

                // Merge if already exists and set otherwise
                if (nt in first_table) {
                    first_table[nt] = chain(first_table[nt].byPair,
                        f.byPair).assocArray;
                } else {
                    first_table[nt] = f;
                }
            }
        }
    }

    /++
     + Initializes 'Follow' sets of each nonterminal.
     +
     + Follow set of a nonterminal contains every token that can appear right
     + after that nonterminal ends.
     + Example: For this grammer.
     + A = xBy | zBq | uBw
     + B = a | b // definition of B doesn't matter in this case
     + Follow(A) = {y, q, w}
     +/
    void initFollow(N starter) {
        follow_table[starter][epsilon] = true;
        bool changed = true;
        while (changed) {
            changed = false;
            // For each nonterminal
            foreach (rule_nt, alts; rule_list) {
                // For each alternative production it has
                foreach (alt_idx, alt; alts) {

                    int[T] trailer;
                    if (rule_nt in follow_table)
                        trailer = follow_table[rule_nt];

                    for (int i = alt.length.to!int-1; i >= 0; i--) {
                        if (alt[i].has!N) {
                            // Initialize the follow table if not present
                            if (alt[i].get!N !in follow_table)
                                follow_table[alt[i].get!N] = null;
                            // Merge nt's follow set and trailer from last iteration
                            auto merged = chain(follow_table[alt[i].get!N].byPair,
                                trailer.byPair).assocArray;

                            // Setting alt[i].get!N's follow table
                            // If this rule adds something in nt's follow set
                            // update the that follow set
                            if (merged != follow_table[alt[i].get!N]) {
                                follow_table[alt[i].get!N] = merged;
                                changed = true;
                            }

                            // Setting trailer for next iteration
                            // If this nt can be empty:
                            if (epsilon in first_table[alt[i].get!N]) {
                                trailer = chain(first_table[alt[i].get!N].byPair,
                                        trailer.byPair).assocArray;
                            } else {
                                trailer = first_table[alt[i].get!N];
                            }
                        } else {
                            // Encountering a token means it will be what
                            // follows the next symbol
                            trailer = null;
                            // TODO: Change trailer into a bool[T]
                            trailer[alt[i].get!T] = 1;
                        }
                    }
                }
            }
        }
    }

    /++
     + Builds LL(1) parsing table using first and follow sets.
     +/
    void buildParsingTable() {
        foreach (nt, rule; rule_list) {
            // For starting productions
            foreach (sym, first_idx; first_table[nt]) {
                parsing_table[nt][sym] = first_idx;
            }
            if (epsilon in first_table[nt]) {
                // Required for ending productions
                foreach (sym, follow_idx; follow_table[nt]) {
                    parsing_table[nt][sym] = first_table[nt][epsilon];
                }
            }
        }
    }

    alias SymbolInfo = SumType!(N, TokenInfo);
    alias CNode = CstNode!SymbolInfo;

    /++
     + Parses the given token_list.
     +
     + Params:
     +      token_list = List of tokens to parse
     + Returns: Root of the parse tree
     +/
    CNode parse(TokenInfo[] token_list) {
        CNode parse_tree = CNode(SymbolInfo(start_nt));

        Tuple!(GrammarSymbol, CNode*)[] nt_stack =
            [tuple(GrammarSymbol(start_nt), &parse_tree)];
        size_t token_cursor = 0;

        while (!nt_stack.empty) {
            auto top = nt_stack.back[0];
            CNode* pt_cursor = nt_stack.back[1];

            if (token_cursor >= token_list.length) {
                writeln("Error: Run out of tokens.");
                writeln(nt_stack);
            }
            auto w = token_list[token_cursor].type;

            if (top.has!T && top.get!T == w) {
                // Matched a token so we advance
                nt_stack.popBack();
                // FIXME: Having seminfo inside cst.type is misleading
                pt_cursor.type.get!TokenInfo.seminfo = token_list[token_cursor].seminfo;
                token_cursor++;
            } else if (top.has!T) {
                // Top symbol is a token but didn't match
                // FIXME: Return the error to the user.
                writefln("Parsing error (Expected token '%s') %d - %s",
                        top.get!T, token_cursor, nt_stack);
                writeln("- Found ", w);
                return parse_tree;
            } else if (top.get!N !in parsing_table || w !in
                    parsing_table[top.get!N]) {
                // Top symbol is a nonterminal but we can not start it from the
                // parsing table
                // FIXME: Return the error to the user.
                writefln("Parsing error (Match error %s) %d - %s", top.get!N, token_cursor, nt_stack);
                return parse_tree;
            } else if (top.get!N in parsing_table && w in
                    parsing_table[top.get!N]) {
                // We start matching of a nonterminal
                nt_stack.popBack();
                pt_cursor.alt_idx = parsing_table[top.get!N][w];
                auto list = rule_list[top.get!N][parsing_table[top.get!N][w]];
                auto size = list.length.to!int-1;
                // We add symbols from the selected production in reverse order
                // so first symbol will be on top of the stack.
                for (int i = size; i >= 0; i--) {
                    // Converting grammar tables SumType to CNode's SumType
                    SymbolInfo si;
                    if (list[i].has!T) {
                        si = TokenInfo(list[i].get!T);
                    } else {
                        si = list[i].get!N;
                    }
                    pt_cursor.addChild(si);
                    nt_stack ~= tuple(list[i], pt_cursor.children.back);
                }
            }
        }

        return parse_tree;
    }

    /++
     + Constructs the parser structure.
     +
     + Params:
     +      rules = Grammar. Keys correspond to nonterminals, values are
     +              productions of that nonterminal. A production is an array of
     +              alternatives which all consist of GrammarSymbols.
     +      start = Starting symbol. This is what will be matched when parse
     +              gets called.
     +/
    this (GrammarSymbol[][][N] rules, N start) {
        rule_list = rules;
        start_nt = start;

        initFirst();
        initFollow(start);
        buildParsingTable();
    }
}

///
unittest {
    enum Tokens {
        Epsilon = 0,
        a, b, c
    }
    enum Nonterms {
        Unknown = 0,
        A, B, C
    }
    alias mParser = Parser!(Tokens, Nonterms);
    alias GS = mParser.GrammarSymbol;
    alias GT = mParser.GrammarTable;
    alias Token = mParser.TokenInfo;

    /*
     * A = BCb | CbBa
     * B = a | c
     * C = b
     */
    GT grammer = [
        Nonterms.A: [
            [GS(Nonterms.B), GS(Nonterms.C), GS(Tokens.b)],
            [GS(Nonterms.C), GS(Tokens.b), GS(Nonterms.B), GS(Tokens.a)]
        ],
        Nonterms.B: [[GS(Tokens.a)], [GS(Tokens.c)]],
        Nonterms.C: [[GS(Tokens.b)]]
    ];

    int[Tokens][Nonterms] expected_first = [
        Nonterms.A: [
            Tokens.a: 0,
            Tokens.c: 0,
            Tokens.b: 1
        ],
        Nonterms.B: [
            Tokens.a: 0,
            Tokens.c: 1,
        ],
        Nonterms.C: [
            Tokens.b: 0,
        ],
    ];

    int[Tokens][Nonterms] expected_follow = [
        Nonterms.A: [
            Tokens.Epsilon: 1,
        ],
        Nonterms.B: [
            Tokens.b: 0,
            Tokens.a: 1,
        ],
        Nonterms.C: [
            Tokens.b: 1,
        ],
    ];

    int[Tokens][Nonterms] expected_parsing_table = [
        Nonterms.A: [
            Tokens.a: 0,
            Tokens.c: 0,
            Tokens.b: 1
        ],
        Nonterms.B: [
            Tokens.a: 0,
            Tokens.c: 1,
        ],
        Nonterms.C: [
            Tokens.b: 0,
        ],
    ];

    mParser parser = mParser(grammer, Nonterms.A);

    if (parser.first_table != expected_first) {
        writeln("Expected: ", expected_first);
        writeln("Found: ", parser.first_table);
        assert(false);
    }

    if (parser.follow_table != expected_follow) {
        writeln("Expected: ", expected_follow);
        writeln("Found: ", parser.follow_table);
        assert(false);
    }

    if (parser.parsing_table != expected_parsing_table) {
        writeln("Expected: ", expected_parsing_table);
        writeln("Found: ", parser.parsing_table);
        assert(false);
    }

    // Tokens[] token_list1 = [Tokens.b, Tokens.b, Tokens.a, Tokens.a]; // A 1
    // auto parse_tree1 = parser.parse(token_list1);
    // assert(parse_tree1.equal());
    // Tokens[] token_list2 = [Tokens.b, Tokens.b, Tokens.c, Tokens.a]; // A 1
    // Tokens[] token_list3 = [Tokens.c, Tokens.b, Tokens.b]; // A 0
    // Tokens[] token_list4 = [Tokens.a, Tokens.b, Tokens.b]; // A 0
}
