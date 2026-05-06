import std.sumtype;

struct Parser(T, N) {
    enum ParserResult {
        Success,
        NoMatch,
        FaultyState,
    }
    alias SymbolType = SumType!(T, N); 
    SymbolType[][N] rule_list;

    T[] token_list;
    size_t token_cursor;
    N[] nt_stack;

    this (T[] tokens) {
        token_list = tokens;
    }

    ParserResult parse() {
        return ParserResult.NoMatch;
    }
}
