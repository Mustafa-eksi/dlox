/// Predictive Parser Implementation
module dlox.parser;

import std.sumtype : SumType, match, has, get;
import std.typecons : Tuple, tuple;
import std.conv : to;
import std.range : empty, back, front, chain;
import std.algorithm.mutation : stripRight, remove, fill;
import std.algorithm.iteration : each;
import std.algorithm.searching : canFind;
import std.array : assocArray, byPair, popBack;
import std.stdio : writeln, writefln;
import std.traits : EnumMembers;

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

struct Parser(T, N, alias rule_list, N start)
    if (is(T : ulong) && is(N : ulong) &&
        is(typeof(rule_list) == SumType!(T, N)[][][(EnumMembers!N).length]))
{
    /// Number of tokens in the T enumeration
    enum TCount = (EnumMembers!T).length;

    /// Number of nonterminals in the T enumeration
    enum NTCount = (EnumMembers!N).length;

    /// Epsilon token. This is used to represent empty productions and end of
    /// input.
    static const T epsilon = cast(T)0;
    alias TokenInfo = Lexer!T.LexerToken;
    alias GrammarSymbol = SumType!(T, N);
    alias GrammarTable = GrammarSymbol[][][NTCount];
    alias SymbolInfo = SumType!(N, TokenInfo);
    alias CNode = CstNode!SymbolInfo;

    alias RuleIndex = Tuple!(int, N);

    /++
     + First table of the grammar. This is a 2D array where first dimension is
     + indexed by nonterminals and second dimension is indexed by tokens. The
     + value of the table is the alternative index of the production rule that
     + can be used to start the nonterminal with the given token. -1 if there
     + is no such production.
     +/
    enum int[TCount][NTCount] first_table = initFirst();

    /++
     + Follow table of the grammar. This is a 2D array where first dimension is
     + indexed by nonterminals and second dimension is indexed by tokens. The
     + value of the table is true if the token can follow the nonterminal.
     +/
    enum bool[TCount][NTCount] follow_table = initFollow(start);

    /++
     + LL(1) parsing table of the grammar. This is a 2D array where first
     + dimension is indexed by nonterminals and second dimension is indexed by
     + tokens. The value of the table is the alternative index of the production
     + rule that can be used to start the nonterminal with the given token. -1
     + if there is no such production.
     +/
    enum int[TCount][NTCount] parsing_table = buildParsingTable();

    /// Applies token set b to a.
    static void applyTokenSet(ref bool[TCount] a, bool[TCount] b) {
        b.each!((i, el) {
            a[i] = el || a[i];
        });
    }

    /// Applies token map b to token set a.
    static void applyTokenMapToSet(ref bool[TCount] a, int[TCount] b) {
        b.each!((tok, val) {
            a[tok] |= val != -1;
        });
    }

    /// Applies token map b to token map a.
    static void applyTokenMap(ref int[TCount] a, int[TCount] b) {
        b.each!((tok, val) {
            if (val != -1)
                a[tok] = val;
        });
    }

    /// Initializes all elements of token set a to b.
    static void initTokenSet(ref bool[TCount] a, bool b) {
        foreach (ref el; a) {
            el = b;
        }
    }

    /// Initializes all elements of token map a to b.
    static void initTokenMap(ref int[TCount] a, int b) {
        foreach (ref el; a) {
            el = b;
        }
    }

    /++
     + Gets first set of the given rule.
     +
     + Params:
     +      nt = Nonterminal of the rule
     +      alt_idx = Which alternative to get first of.
     + Returns: First set of the given rule.
     +/
    static int[TCount] getFirst(N nt, int alt_idx) {
        int[TCount] output;
        initTokenMap(output, -1);
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
                applyTokenMap(output, ff);
            }
            // Since output is from getFirst, their values will be the
            // alternative indices of f. We have to set them all to alt_idx.
            foreach (tok, ref alt; output) {
                if (alt != -1)
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
    static int[TCount][NTCount] initFirst() {
        int[TCount][NTCount] output;
        foreach (nt, ref fs; output) {
            foreach(token, ref alt; fs) {
                alt = -1;
            }
        }
        // This iterates every production
        foreach (nt, rule; rule_list) {
            foreach (alt_idx, _; rule) {
                // Calls the recursive function
                auto f = getFirst(nt.to!N, alt_idx.to!int);
                applyTokenMap(output[nt], f);
            }
        }
        return output;
    }

    /++
     + Initializes 'Follow' sets of each nonterminal.
     +
     + Follow set of a nonterminal contains every token that can appear right
     + after that nonterminal ends.
     + Example: For this grammar.
     + A = xBy | zBq | uBw
     + B = a | b // definition of B doesn't matter in this case
     + Follow(A) = {y, q, w}
     +/
    static bool[TCount][NTCount] initFollow(N starter) {
        bool[TCount][NTCount] output;
        output[starter][epsilon] = true;
        bool changed = true;
        while (changed) {
            changed = false;
            // For each nonterminal
            foreach (rule_nt, alts; rule_list) {
                // For each alternative production it has
                foreach (alt_idx, alt; alts) {
                    bool[TCount] trailer = output[rule_nt].dup;

                    for (int i = alt.length.to!int-1; i >= 0; i--) {
                        if (alt[i].has!N) {
                            // Merge nt's follow set and trailer from last iteration
                            bool[TCount] merged = output[alt[i].get!N].dup;
                            applyTokenSet(merged, trailer);

                            // Setting alt[i].get!N's follow table
                            // If this rule adds something in nt's follow set
                            // update the that follow set
                            if (merged != output[alt[i].get!N]) {
                                output[alt[i].get!N] = merged;
                                changed = true;
                            }

                            // Setting trailer for next iteration
                            // If this nt can be empty:
                            if (first_table[alt[i].get!N][epsilon] != -1) {
                                applyTokenMapToSet(trailer, first_table[alt[i].get!N]);
                            } else {
                                initTokenSet(trailer, false);
                                applyTokenMapToSet(trailer, first_table[alt[i].get!N]);
                            }
                        } else {
                            // Encountering a token means it will be what
                            // follows the next symbol
                            initTokenSet(trailer, false);
                            // TODO: Change trailer into a bool[T]
                            trailer[alt[i].get!T] = true;
                        }
                    }
                }
            }
        }
        return output;
    }

    /++
     + Builds LL(1) parsing table using first and follow sets.
     +/
    static int[TCount][NTCount] buildParsingTable() {
        int[TCount][NTCount] output;
        foreach (nt, ref fs; output) {
            foreach(token, ref alt; fs) {
                alt = -1;
            }
        }
        foreach (nt, rule; rule_list) {
            // For starting productions
            foreach (sym, first_idx; first_table[nt]) {
                output[nt][sym] = first_idx;
            }
            if (first_table[nt][epsilon] != -1) {
                // Required for ending productions
                foreach (sym, fol; follow_table[nt]) {
                    if (!fol)
                        continue;
                    output[nt][sym] = first_table[nt][epsilon];
                }
            }
        }
        return output;
    }


    /++
     + Parses the given token_list.
     +
     + Params:
     +      token_list = List of tokens to parse
     + Returns: Root of the parse tree
     +/
    CNode parse(TokenInfo[] token_list) {
        CNode parse_tree = CNode(SymbolInfo(start));

        Tuple!(GrammarSymbol, CNode*)[] nt_stack =
            [tuple(GrammarSymbol(start), &parse_tree)];
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
            } else if (parsing_table[top.get!N][w] == -1) {
                // Top symbol is a nonterminal but we can not start it from the
                // parsing table
                // FIXME: Return the error to the user.
                writefln("Parsing error (Match error %s) %d - %s", top.get!N, token_cursor, nt_stack);
                return parse_tree;
            } else if (parsing_table[top.get!N][w] != -1) {
                // We start matching of a nonterminal
                nt_stack.popBack();
                pt_cursor.alt_idx = parsing_table[top.get!N][w];
                auto list = rule_list[top.get!N][parsing_table[top.get!N][w]];
                const auto size = list.length.to!int-1;
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
}

///
unittest {
    import std.algorithm.iteration : map;
    import std.array : array;
    enum Tokens {
        Epsilon = 0,
        a, b, c
    }
    enum Nonterms {
        Unknown = 0,
        A, B, C
    }

    alias GS = SumType!(Tokens, Nonterms);
    alias GT = GS[][][EnumMembers!Nonterms.length];
    enum GT GRAMMAR = [
        Nonterms.A: [
            [GS(Nonterms.B), GS(Nonterms.C), GS(Tokens.b)],
            [GS(Nonterms.C), GS(Tokens.b), GS(Nonterms.B), GS(Tokens.a)]
        ],
        Nonterms.B: [[GS(Tokens.a)], [GS(Tokens.c)]],
        Nonterms.C: [[GS(Tokens.b)]]
    ];
    alias mParser = Parser!(Tokens, Nonterms, GRAMMAR, Nonterms.A);
    alias Token = mParser.TokenInfo;
    alias CNode = mParser.CNode;
    alias SI = mParser.SymbolInfo;

    /*
     * A = BCb | CbBa
     * B = a | c
     * C = b
     */

    int[mParser.TCount][mParser.NTCount] expected_first = [
        Nonterms.A: [
            Tokens.a: 0,
            Tokens.b: 1,
            Tokens.c: 0,
            Tokens.Epsilon: -1,
        ],
        Nonterms.B: [
            Tokens.a: 0,
            Tokens.c: 1,
            Tokens.b: -1,
            Tokens.Epsilon: -1,
        ],
        Nonterms.C: [
            Tokens.b: 0,
            Tokens.a: -1,
            Tokens.c: -1,
            Tokens.Epsilon: -1,
        ],
    ];
    mParser.initTokenMap(expected_first[0], -1);

    bool[mParser.TCount][mParser.NTCount] expected_follow = [
        Nonterms.A: [
            Tokens.Epsilon: true,
        ],
        Nonterms.B: [
            Tokens.b: true,
            Tokens.a: true,
        ],
        Nonterms.C: [
            Tokens.b: true,
        ],
    ];

    int[mParser.TCount][mParser.NTCount] expected_parsing_table = [
        Nonterms.A: [
            Tokens.a: 0,
            Tokens.c: 0,
            Tokens.b: 1,
            Tokens.Epsilon: -1,
        ],
        Nonterms.B: [
            Tokens.a: 0,
            Tokens.c: 1,
            Tokens.Epsilon: -1,
            Tokens.b: -1,
        ],
        Nonterms.C: [
            Tokens.b: 0,
            Tokens.Epsilon: -1,
            Tokens.a: -1,
            Tokens.c: -1,
        ],
    ];
    mParser.initTokenMap(expected_parsing_table[0], -1);

    mParser parser = mParser();

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

    Tokens[] token_list1 = [Tokens.b, Tokens.b, Tokens.a, Tokens.a]; // A 1
    auto parse_tree1 = parser.parse(token_list1.map!(a => Token(a, "")).array);
    CNode root = CNode(SI(Nonterms.A));
    root.alt_idx = 1;
    root.addChild(SI(Token(Tokens.a)));
    root.addChild(SI(Nonterms.B));
    root.children[1].alt_idx = 0;
    root.children[1].addChild(SI(Token(Tokens.a)));
    root.addChild(SI(Token(Tokens.b)));
    root.addChild(SI(Nonterms.C));
    root.children[3].alt_idx = 0;
    root.children[3].addChild(SI(Token(Tokens.b)));
    assert(parse_tree1.equal(root));
}

