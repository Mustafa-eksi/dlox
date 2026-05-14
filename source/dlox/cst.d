/// Concrete Syntax Tree Node.
module dlox.cst;

import std.array : empty;
import std.stdio : write, writeln;
import std.conv : to;

/++
 + Concrete Syntax Tree Node.
 +
 + Params:
 +      Sym = Symbol type, could be anything
 +/
struct CstNode(Sym) {
    Sym type;
    int alt_idx = -1;
    CstNode*[] children;
    CstNode* parent;

    /++
     + Adds child with the `type`.
     +
     + Params:
     +      type = Content of the child.
     +/
    void addChild(Sym type) {
        children ~= new CstNode(type);
        children[$-1].parent = &this;
    }

    /// Prints the node and all its children in a readable way.
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

    /++
     + Checks whether this and node is equivalent (including children)
     +
     + Params:
     +      node = CstNode to check against
     + Returns: True if two trees are equivalent
     +/
    bool equal(CstNode!Sym node) {
        if (node.type != type)
            return false;
        if (node.alt_idx != alt_idx)
            return false;
        if (node.children.length != children.length)
            return false;
        foreach (i, ch; children) {
            if (!ch.equal(*node.children[i]))
                return false;
        }
        return true;
    }
}

///
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

unittest {
    import std.random : uniform;
    import std.range : front;
    for (int fuzz = 0; fuzz < 50; fuzz++) {
        alias CNode = CstNode!int;
        CNode root = CNode(0);
        int count = uniform(50, 100);
        int level = uniform(10, 15);
        for (int i = 0; i < count; i++) {
            root.addChild(i);
            CNode *c = root.children[i];
            for (int j = 0; j < level; j++) {
                c.addChild(i*(j+1));
                c = c.children.front;
            }
        }
        for (int i = 0; i < count; i++) {
            assert(root.children[i].type == i);
            CNode *c = root.children[i];
            c = c.children.front;
            for (int j = 0; j < level-1; j++) {
                assert(c.children.length == 1);
                assert(c.type == i*(j+1));
                c = c.children.front;
            }
        }
    }
}
