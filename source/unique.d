/*
MIT License
Copyright (c) 2017 Boris Barboris
*/

module daii.unique;

import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional: forward;
import std.traits: isArray, isAbstractClass, isAssignable;

import daii.utils;

/// Unique memory owner, holds one instance of type T. Don't use it to hold
/// built-in arrays, use custom array type instead. Deallocates in destructor.
struct Unique(T, Allocator = Mallocator)
    if (isAllocator!Allocator && !isArray!T)
{
    enum HoldsAllocator = !isStaticAllocator!Allocator;

    static if (isClassOrIface!T)
    {
        alias PtrT = T;
        @property inout(T) v() inout @nogc @safe
        {
            assert(valid);
            return ptr;
        }
    }
    else
    {
        alias PtrT = T*;
        @property ref inout(T) v() inout @nogc @safe
        {
            assert(valid);
            return *ptr;
        }
    }

    private PtrT ptr;

    @property bool valid() const @safe @nogc { return ptr !is null; }

    @disable this();

    static if (HoldsAllocator)
        private Allocator allocator;

    // don't generate constructors for abstract types
    static if (!(is(T == interface) || isAbstractClass!(T)))
    {
        static if (!HoldsAllocator)
        {
            private this(PtrT ptr) @safe @nogc
            {
                this.ptr = ptr;
            }

            // factory function for types with parameterless constructors
            static Unique!(T, Allocator) make(Args...)(auto ref Args args)
            {
                auto ptr = Allocator.instance.make!(T)(forward!args);
                auto uq = Unique!(T, Allocator)(ptr);
                assert(uq.valid);
                return uq;
            }
        }
        else
        {
            private this(PtrT ptr, Allocator alloc) @safe @nogc
            {
                this.ptr = ptr;
                this.allocator = alloc;
            }

            static Unique!(T, Allocator) make(Args...)(auto ref Allocator alloc,
                auto ref Args args)
            {
                auto ptr = alloc.make!T(forward!args);
                auto uq = Unique!(T, Allocator)(ptr, alloc);
                assert(uq.valid);
                return uq;
            }
        }
    }

    // Templated copy constructor for polymorphic upcasting.
    this(DT)(scope auto ref Unique!(DT, Allocator) rhs)
    {
        static if (isClassOrIface!T)
            static assert(isAssignable!(T, DT));
        else
            static assert(is(T == DT));
        assert(rhs.valid);
        this.ptr = rhs.ptr;
        rhs.ptr = null;
        static if (HoldsAllocator)
            this.allocator = rhs.allocator;
    }

    static if (isClassOrIface!T)
    {
        // Polymorphic upcast with ownership transfer
        Unique!(BT, Allocator) to(BT)()
            if (isClassOrIface!BT && isAssignable!(BT, T))
        {
            Unique!(BT, Allocator) rv = Unique!(BT, Allocator)(this);
            assert(rv.valid);
            assert(!valid);
            return rv;
        }
    }

    // move ownership to new rvalue Unique
    Unique!(T, Allocator) move()
    {
        auto rv = Unique!(T, Allocator)(this);
        assert(!valid);
        return rv;
    }

    // bread and butter
    ~this()
    {
        destroy();
    }

    // destroy the resource (destructor + free memory)
    void destroy()
    {
        if (valid)
        {
            static if (HoldsAllocator)
                allocator.dispose(ptr);
            else
                Allocator.instance.dispose(ptr);
            ptr = null;
        }
    }

    // no ownership transfers, use move and construct new uniqueptr
    @disable this(this);
    @disable ref Unique!(T, Allocator) opAssign(DT)(Unique!(DT, Allocator) rhs);
    @disable ref Unique!(T, Allocator) opAssign(DT)(ref Unique!(DT, Allocator) rhs);
}

unittest
{
    auto uq = Unique!int.make(5);
    assert(uq.valid);
    assert(uq.v == 5);
    uq.v = 7;
    assert(uq.v == 7);
}

unittest
{
    auto create_uniq()
    {
        return Unique!int.make(0);
    }
    void consume_uniq(Unique!int u)
    {
        assert(u.valid);
        assert(u.v == 5);
    }
    auto u = create_uniq();
    assert(u.valid);
    assert(u.v == 0);
    u.v = 5;
    consume_uniq(u.move);
    assert(!u.valid);
}

unittest
{
    struct TS
    {
        int x = -3;
    }
    auto u = Unique!TS.make;
    assert(u.v.x == -3);
}

unittest
{
    static int count = 0;
    static int total = 0;
    class TC
    {
        this() { count++; total++; }
        ~this() { count--; }
        int j = 3;
    }
    auto u1 = Unique!TC.make;
    assert(count == 1);
    {
        auto u2 = Unique!TC.make;
        assert(count == 2);
        assert(u2.v !is null);
        assert(u2.v.j == 3);
    }
    assert(count == 1);
    assert(total == 2);
}

import std.experimental.allocator.showcase;

unittest
{
    static int count = 0;
    static int total = 0;
    class TC
    {
        this() { count++; total++; }
        ~this() { count--; }
        int j = 3;
    }
    alias Alloc = StackFront!(4096, Mallocator);
    Alloc al;
    alias Uq = Unique!(TC, Alloc*);
    auto u1 = Uq.make(&al);
    assert(count == 1);
    {
        auto u2 = Uq.make(&al);
        assert(count == 2);
        assert(u2.v !is null);
        assert(u2.v.j == 3);
    }
    assert(count == 1);
    assert(total == 2);
}

unittest
{
    class A {}
    class B: A {}
    Unique!A uq = Unique!B.make();
    assert(uq.valid);
}

unittest
{
    static int ades = 0;
    static int bdes = 0;
    class A { ~this() {ades++;}}
    class B: A { ~this(){bdes++;}}
    {
        Unique!A aq = Unique!A.make();
        {
            Unique!A bq = Unique!B.make();
            assert(ades == 0);
            assert(bdes == 0);
        }
        assert(ades == 1);
        assert(bdes == 1);
        Unique!A cq = aq.move;
        assert(!aq.valid);
    }
    assert(ades == 2);
    assert(bdes == 1);
}

unittest
{
    static int ades = 0;
    static int bdes = 0;
    class A { ~this() {ades++;}}
    class B: A { ~this(){bdes++;}}
    void consume(Unique!A uq)
    {
        assert(uq.valid);
        assert(ades == 0);
        assert(bdes == 0);
    }
    {
        Unique!B aq = Unique!B.make();
        consume(aq.to!A);
        assert(ades == 1);
        assert(bdes == 1);
    }
    assert(ades == 1);
    assert(bdes == 1);
}
