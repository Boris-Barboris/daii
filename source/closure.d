/*
MIT License
Copyright (c) 2017 Boris Barboris
*/

module daii.closure;

import std.conv: to;
import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional: forward;

import daii.refcounted;
import daii.utils;


/// Abstract callable object.
abstract class Closure(Ret, Args...)
{
    Ret call(Args args) @trusted;
}

template AllocationContext(Allocator = Mallocator, bool Atomic = true)
{
    template CtxRefCounted(T)
    {
        alias CtxRefCounted = RefCounted!(T, Atomic, Allocator);
    }

    /// RAII wrapper for callable closure.
    struct Delegate(Ret, Args...)
    {
        @disable this();

        private this(CtxRefCounted!(Closure!(Ret, Args)) clos) @safe
        {
            _closure = clos;
        }

        CtxRefCounted!(Closure!(Ret, Args)) _closure;

        bool opEquals(const ref Delegate!(Ret, Args) s) const @safe @nogc
        {
            return _closure.v is s._closure.v;
        }

        bool opEquals(const Delegate!(Ret, Args) s) const @safe
        {
            return _closure.v is s._closure.v;
        }

        Ret opCall(Args args) @safe
        {
            return _closure.v.call(forward!args);
        }
    }

    /// Bread and butter
    auto autodlg(ExArgs...)(ExArgs exargs) @safe
    {
        static if (isStaticAllocator!Allocator)
            enum f_idx = 0; // index of function in exargs
        else
        {
            static assert(isAllocator!(ExArgs[0]));
            enum f_idx = 1; // 0 is allocator instance
        }
        static assert(ExArgs.length > f_idx);
        static assert(isFunctionPointerType!(ExArgs[f_idx]));

        // return type of the delegate
        alias RetType = ReturnType!(ExArgs[f_idx]);
        alias AllArgs = ParamTypes!(ExArgs[f_idx]);

        static assert(AllArgs.length >= (ExArgs.length - 1 - f_idx));

        // Actual type of a delegate is deduced here. Arguments of function
        // passed by programmer are reduced until all captured variables are
        // bound to respective parameters in the function.

        // This is how many arguments are in the resulting delegate type opCall.
        enum int dlgArgCount = AllArgs.length - ExArgs.length + 1 + f_idx;

        // Deleagte argument types are taken from the function pointer
        alias DlgArgs = Take!(dlgArgCount, AllArgs);

        // Captured variable types are taken from, surprise, captured variables,
        // passed after the function in exargs.
        alias CapturedArgs = Skip!(1 + f_idx, ExArgs);

        static class CClosure: Closure!(RetType, DlgArgs)
        {
            RetType function(AllArgs) _f;

            // captured variables are mixed-in inside class body
            mixin(fieldExpand!(CapturedArgs.length, "CapturedArgs"));

            this(RetType function(AllArgs) f, CapturedArgs cpt) @safe
            {
                _f = f;
                foreach (i, field; CapturedArgs)
                {
                    // captured fields are named field0, field1 ...
                    mixin("this.field" ~ to!string(i)) = cpt[i];
                }
            }

            override RetType call(DlgArgs args) @trusted
            {
                static if (CapturedArgs.length > 0)
                {
                    enum string captee_fields =
                        fieldsToParamListStr(CapturedArgs.length);
                    return _f(forward!args, mixin(captee_fields));
                }
                else
                    return _f(forward!args);
            }
        }

        // reference-counted closure is constructed...
        CtxRefCounted!(Closure!(RetType, DlgArgs)) rfc =
            CtxRefCounted!(CClosure).make(exargs);
        // and passed to the delegate
        Delegate!(RetType, DlgArgs) dlg = Delegate!(RetType, DlgArgs)(rfc);
        return dlg;
    }
}

unittest
{
    alias Dlg = AllocationContext!(Mallocator, true).Delegate!(void, int);
    static int counter = 0;
    static int ccount = 0;
    class CClosure: Closure!(void, int)
    {
        this() { ccount++; }
        ~this() { ccount--; }
        override void call(int v) { counter++; }
    }
    {
        RefCounted!(Closure!(void, int)) rfc = RefCounted!CClosure.make;
        Dlg dlg = Dlg(rfc);
        dlg(3);
        dlg(-1);
        assert(counter == 2);
        assert(ccount == 1);
    }
    assert(ccount == 0);
}

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(void, int);
    int sum = 0;
    int[] arr = [3, 5, 1, 9, 4];
    void map(int[] arr, Dlg dlg)
    {
        for (int i = 0; i < arr.length; i++)
            dlg(arr[i]);
    }
    Dlg d = Ctx.autodlg((int x, int* s) { *s += x; }, &sum);
    map(arr, d);
    assert(sum == 22);
}

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(int, int, int);
    int[] arr = [3, 5, 1, 9, 4];
    int reduce(D)(int[] arr, D dlg)
    {
        int res = dlg(arr[0], arr[1]);
        for (int i = 2; i < arr.length; i++)
            res = dlg(res, arr[i]);
        return res;
    }
    Dlg d = Ctx.autodlg((int x, int y) => x + y);
    int sum = reduce(arr, d);
    assert(sum == 22);
}

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(void);
    Dlg d = Ctx.autodlg((){});
    d();
}

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(int, int, float);
    Dlg d = Ctx.autodlg((int x, float y){ return 3;});
    d(4, 4.0f);
}

import std.experimental.allocator.showcase;

unittest
{
    alias AllocType = StackFront!(4096, Mallocator);
    AllocType al;
    alias Ctx = AllocationContext!(AllocType*, true);
    alias Dlg = Ctx.Delegate!(int, int, float);
    Dlg d = Ctx.autodlg(&al, (int x, float y){ return 3;});
    d(4, 4.0f);
}
