import std.array : empty;
import std.stdio : write, writeln;
import std.conv : to;

struct CstNode(Sym) {
    Sym type;
    int alt_idx = -1;
    CstNode*[] children;
    CstNode* parent;

    void addChild(Sym type) {
        // writeln(" - addChild ", type, " to ", this);
        children ~= new CstNode(type);
        children[$-1].parent = &this;
    }

    void print(int level=0) {
        for (int i = 0; i < level; i++)
            write("\t");
        write(type);
        write(" (", alt_idx, ")");
        if (!children.empty)
            write(":");
        writeln();
        for (int i = children.length.to!int-1; i >= 0; i--) {
            children[i].print(level+1);
        }
    }
}

unittest {
    enum Tok {
        EPSILON,
        IDENTIFIER,
        PLUS,
    }
    CstNode!Tok root = CstNode!Tok(Tok.EPSILON);
    root.addChild(Tok.IDENTIFIER);
    root.addChild(Tok.IDENTIFIER);
    root.addChild(Tok.IDENTIFIER);
    foreach (ref ch; root.children) {
        ch.addChild(Tok.PLUS);
    }
    foreach (ref ch; root.children) {
        assert(ch.parent == &root && ch.type == Tok.IDENTIFIER);
        foreach (ref ch2; ch.children) {
            assert(ch2.parent == ch && ch2.type == Tok.PLUS);
        }
    }
}
