/// Predictive Parser Implementation
module dlox.parser;

import std.sumtype : SumType, match, has, get;
import std.typecons : Tuple, tuple;
import std.conv : to;
import std.range : empty, back, front, chain;
import std.algorithm.mutation : stripRight;
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
     + Initializers "First" sets of each nonterminal.
     +
     + First set of a nonterminal includes every token that can be the leftmost
     + symbol of that nonterminal.
     + Example: For this production
     + A = xyz | bcde | efg
     + First(A) = {x, b, e}
     +/
    void initFirst() {
        // TODO: Require epsilon token in 'empty' productions
        /* Algorithm:
            For each non-terminal
                push it to stack
                while stack is not empty
                    A = back of the stack
                    for each alternative of A
                        if it is empty
                            rewind the stack and add them epsilon
                        if alternative has a nonterminal as its first symbol
                            add it to the stack
                        else (if it is a token)
                            rewind the stack and add them that symbol
         */
        foreach (nt, r; rule_list) {
            RuleIndex[] st;
            st ~= RuleIndex(0, nt);

            while (!st.empty) {
                const RuleIndex[] cpy_st = st;
                foreach (i, sub_alt; rule_list[st.back[1]]) {
                    // writeln("=== ", i);
                    // writeln(st);

                    st.back[0] = i.to!int;
                    // FIXME: This is problematic
                    if (sub_alt.empty) {
                        // writeln("Subalt empty");
                        for (int j = cpy_st.length.to!int-1; j >= 0; j--) {
                            N jnt = cpy_st[j][1];
                            int jalt = cpy_st[j][0];
                            if (jnt !in first_table || epsilon !in first_table[jnt])
                            {
                                // writefln("     = inserting into -> %s", rs);
                                first_table[jnt][epsilon] = jalt;
                            }
                        }
                        continue;
                    }

                    if (sub_alt.front.has!N) {
                        st ~= RuleIndex(0, sub_alt[0].get!N);
                        // writefln(" - %s: %d", sub_alt[0].get!N, i);
                        // writefln("   st: %s", st);
                        // writefln("   sub_alt: %s", sub_alt);
                    } else {
                        // writefln(" = found -> %s", sub_alt[0].get!T);
                        for (int j = cpy_st.length.to!int-1; j >= 0; j--) {
                            N jnt = cpy_st[j][1];
                            int jalt = cpy_st[j][0];
                            // writeln(jnt, jalt);
                            if (jnt !in first_table || sub_alt.front.get!T !in
                                    first_table[jnt]) {
                                // writefln("     = inserting into -> %s", rs);
                                first_table[jnt][sub_alt.front.get!T] = jalt;
                            }
                        }
                    }
                }

                if (cpy_st == st) {
                    break;
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
            foreach (rule_nt, alts; rule_list) {
                foreach (alt_idx, alt; alts) {
                    int[T] trailer;
                    if (rule_nt in follow_table)
                        trailer = follow_table[rule_nt];
                    for (int i = alt.length.to!int-1; i >= 1; i--) {
                        if (alt[i].has!N) {
                            if (alt[i].get!N !in follow_table)
                                follow_table[alt[i].get!N] = null;
                            auto merged = chain(follow_table[alt[i].get!N].byPair,
                                trailer.byPair).assocArray;
                            if (merged != follow_table[alt[i].get!N]) {
                                follow_table[alt[i].get!N] = merged;
                                changed = true;
                            }
                            if (epsilon in first_table[alt[i].get!N]) {
                                trailer = chain(first_table[alt[i].get!N].byPair,
                                        trailer.byPair).assocArray;
                            } else {
                                trailer = first_table[alt[i].get!N];
                            }
                        } else {
                            trailer = null;
                            trailer[alt[i].get!T] = alt_idx.to!int;
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
            foreach (sym, first_idx; first_table[nt]) {
                parsing_table[nt][sym] = first_idx;
            }
            if (epsilon in first_table[nt]) {
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
                nt_stack.popBack();
                // FIXME: Having seminfo inside cst.type is misleading
                pt_cursor.type.get!TokenInfo.seminfo = token_list[token_cursor].seminfo;
                token_cursor++;
            } else if (top.has!T) {
                // FIXME: Return the error to the user.
                writefln("Parsing error (Expected token '%s') %d - %s",
                        top.get!T, token_cursor, nt_stack);
                writeln("- Found ", w);
                return parse_tree;
            } else if (top.get!N !in parsing_table || w !in
                    parsing_table[top.get!N]) {
                // FIXME: Return the error to the user.
                writefln("Parsing error (Match error %s) %d - %s", top.get!N, token_cursor, nt_stack);
                return parse_tree;
            } else if (top.get!N in parsing_table && w in
                    parsing_table[top.get!N]) {
                nt_stack.popBack();
                pt_cursor.alt_idx = parsing_table[top.get!N][w];
                auto list = rule_list[top.get!N][parsing_table[top.get!N][w]];
                auto size = list.length.to!int-1;
                for (int i = size; i >= 0; i--) {
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
        import std.stdio;
        start_nt = start;
        initFirst();
        initFollow(start);
        buildParsingTable();
    }
}
