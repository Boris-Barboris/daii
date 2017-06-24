/*
MIT License
Copyright (c) 2017 Boris Barboris
*/

module daii.utils;

import std.conv: to;
import std.experimental.allocator: make, dispose;
import std.traits: Unqual, isArray;
import std.meta: AliasSeq;


template isAllocator(T)
{
    // Credits to atila.
    // https://github.com/atilaneves/automem/blob/master/source/automem/traits.d
    private template isAllocatorAlike(T)
    {
        enum isAllocatorAlike = is(typeof(()
            {
                T allocator;
                int* i = allocator.make!int;
                allocator.dispose(i);
                void[] bytes = allocator.allocate(size_t.init);
                bool res = allocator.deallocate(bytes);
            }));
    }
    enum isAllocator = isAllocatorAlike!(Unqual!T) ||
        isAllocatorAlike!(shared Unqual!T);
}

template isStaticAllocator(T)
    if (isAllocator!T)
{
    static if (is(typeof(T.instance)))
        enum isStaticAllocator = isAllocator!(typeof(T.instance));
    else
        enum isStaticAllocator = false;
}

unittest
{
    import std.experimental.allocator.showcase: StackFront;
    import std.experimental.allocator.mallocator: Mallocator;

    static assert(isAllocator!Mallocator);
    static assert(isStaticAllocator!Mallocator);
    static assert(!isAllocator!int);
    static assert(isAllocator!(StackFront!4096));
    static assert(!isStaticAllocator!(StackFront!4096));
}

package string fieldExpand(int count, string arrname)()
{
    string result = "";
    for (int i = 0; i < count; i++)
    {
        string idx_str = to!string(i);
        result ~= arrname ~ "[" ~ idx_str ~ "] field" ~ idx_str ~ ";";
    }
    return result;
}

package string argsAndFields(uint count1, string G1, uint count2)()
{
    string result = "";
    for (uint i = 0; i < count1; i++)
        result ~= G1 ~ "[" ~ to!string(i) ~ "], ";
    for (uint i = 0; i < count2; i++)
    {
        result ~= "this.field" ~ to!string(i);
        if (i < count2 - 1)
            result ~= ", ";
    }
    return result;
}

template isFunctionPointerType(T: FT*, FT)
{
    enum isFunctionPointerType = is(FT == function);
}

unittest
{
    auto p = (){};
    static assert(isFunctionPointerType!(typeof(p)));
}

template ReturnType(FuncType: FT*, FT)
{
    static if (is(FT RT == return))
        alias ReturnType = RT;
    else
        static assert(0, "FuncType must be function pointer type");
}

template ParamTypes(FuncType: FT*, FT)
{
    static if (is(FT Params == function))
        alias ParamTypes = Params;
    else
        static assert(0, "FuncType must be function pointer type");
}

unittest
{
    auto p = (int x){ return x; };
    static assert(is(ReturnType!(typeof(p)) == int));
    static assert(is(ParamTypes!(typeof(p)) == AliasSeq!int));
}

template Take(int count, T...)
{
    alias Take = T[0 .. count];
}

unittest
{
    alias res = Take!(2, int, int, int, float);
    static assert(is(res == AliasSeq!(int, int)));
    static assert(!is(res == AliasSeq!(int, float)));
}

template Skip(int count, T...)
{
    alias Skip = T[count .. $];
}

unittest
{
    alias res = Skip!(1, int, int, int, float);
    static assert(is(res == AliasSeq!(int, int, float)));
}

template isClassOrIface(T)
{
    enum isClassOrIface = is(T == class) || is(T == interface);
}
