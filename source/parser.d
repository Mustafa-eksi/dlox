import std.sumtype : SumType, match, has, get;
import std.typecons : Tuple;
import std.conv : to;
import std.range : empty, back, front, chain;
import std.algorithm.mutation : stripRight;
import std.algorithm.searching : canFind;
import std.array : assocArray, byPair;

/* TODO:
 * 1- Left recursion elimination
 * 2- Left factoring (for predictive parsing)
 *      - When left factored most grammars are LL(1)
 * 3- Check if the grammar is LL(1)
 */

/*
 * @brief Parser template creates a LL(1) parser for the given grammar and
 * tokens.
 * @param T Token enumeration type. T should has 0 reserved as EOF/EPSILON.
 * Naming doesn't matter but don't use 0 for different things.
 * @param N Nonterminal enumeration type
 */
struct Parser(T, N) {
    const T epsilon = cast(T)0;
    enum ParserResult {
        Success,
        NoMatch,
        FaultyState,
    }
    struct ParserError {
        ParserResult type;
        size_t line, column;
    }
    alias GrammarSymbol = SumType!(T, N);
    alias GrammarTable = GrammarSymbol[][][N];
    GrammarTable rule_list;
    ParserError error;

    T[] token_list;
    size_t token_cursor;
    N[] nt_stack;

    alias RuleIndex = Tuple!(int, int);
    RuleIndex[T][N] parsing_table;
    RuleIndex start_nt;

    bool[T][N] first_table;
    bool[T][N] follow_table;

    void initFirst() {
        // bool stillChanging = true;
        // while (stillChanging) {
        //     stillChanging = false;
        //     foreach (rule; rule_list) {
        //         foreach (alternative; rule) {
        //
        //         }
        //     }
        // }
        foreach (nt, r; rule_list) {
            N[] st;
            st ~= nt;
            // writefln("First(%s)", nt);
            while (!st.empty) {
                const N[] cpy_st = st;
                foreach (sub_alt; rule_list[st.back]) {
                    // FIXME: This is problematic
                    if (sub_alt.empty) {
                        foreach (rs; cpy_st) {
                            if (rs !in first_table ||
                                epsilon !in first_table[rs])
                            {
                                // writefln("     = inserting into -> %s", rs);
                                first_table[rs][epsilon] = true;
                            }
                        }
                        continue;
                    }
                    if (sub_alt.front.has!N) {
                        st ~= sub_alt[0].get!N;
                        // writefln(" - %s:", sub_alt[0].get!N);
                    } else {
                        // writefln(" = found -> %s", sub_alt[0].get!T);
                        foreach (rs; cpy_st) {
                            if (rs !in first_table || sub_alt.front.get!T !in first_table[rs]) {
                                // writefln("     = inserting into -> %s", rs);
                                first_table[rs][sub_alt.front.get!T] = true;
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

    void initFollow(N starter) {
        follow_table[starter][epsilon] = true;
        bool changed = true;
        while (changed) {
            changed = false;
            foreach (rule_nt, alts; rule_list) {
                foreach (alt; alts) {
                    bool[T] trailer;
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
                            trailer[alt[i].get!T] = true;
                        }
                    }
                }
            }
            // foreach (rule; rule_list) {
            //     foreach (alt; rule) {
            //         foreach (i, gs; alt) {
            //             if (gs.has!T) continue;
            //             N[] st;
            //             st ~= gs.get!N;
            //             while (!st.empty) {
            //                 T[] f;
            //                 if (i+1 == alt.length) {
            //                 }
            //                 if (alt[i+1].has!T) {
            //                     f ~= alt[i+1].get!T;
            //                 } else {
            //                     // auto next_nt = alt[i+1].get!N;
            //                     // if (next_nt !in first_table ||
            //                     //         first_table[next_nt].empty)
            //                     // f ~= first_table[next_nt];
            //                 }
            //
            //                 foreach (tf; f) {
            //                     if (gs.get!N in follow_table && follow_table[gs.get!N].canFind(tf))
            //                         continue;
            //                     follow_table[gs.get!N] ~= tf;
            //                 }
            //                 continue;
            //             }
            //         }
            //     }
            // }
        }
    }

    this (T[] tokens, GrammarSymbol[][][N] rules, N start) {
        token_list = tokens;
        rule_list = rules;
        import std.stdio;
        writeln("---");
        writeln(rules);
        writeln("---");
        // start_nt = start;
        initFirst();
        initFollow(start);
    }

    void generateParsingTable() {
    }

    ParserResult parse() {
        return ParserResult.NoMatch;
    }


}
