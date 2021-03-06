# daii - Allocator-friendly RAII primitives for D programming language.
## Overview
daii provides commonly-used in C++ scope-based RAII paradigm primitives:   
* Unique - unique pointer.
* RefCounted - reference-counting pointer.   

It also provides Delegate type - mechanism to easily build allocator-aware closures.

I would like to thank @atilaneves for his wonderful library automem, wich inspired
daii.
## Examples
### Setup
```d
import daii;

// Create a shortcut to allocation context:
import std.experimental.allocator.mallocator: Mallocator;
alias MallocCtx = AllocationContext!(Mallocator, true);
// MyCtx will contain primitives, that use static malloc and atomic operations
// where applicable. Currently, Atomic option is only used in reference counter
// decrement\increment of RefCounted struct.

// Create some aliases up to your taste
alias Unique = MallocCtx.Unique;
alias RefCounted = MallocCtx.RefCounted;
alias Delegate = MallocCtx.Delegate;
alias autodlg = MallocCtx.autodlg;
```
### Unique
```d
static int ades = 0;
class A { ~this() { ades++; } }
static int bdes = 0;
class B: A
{
    this(int x_init) { x = x_init; }
    int x;
    ~this(){ bdes++; }
}
{
    Unique!A aq = Unique!A.make();
    {
        Unique!A bq = Unique!B.make(5);  // supports upcasting
        // Unique is not a proxy for the resource,
        // access underlying object by .v property.
        B val = cast(B) bq.v;
        assert(val.x == 5);
        val.x = 4;
        assert(val.x == 4);
    }   // bq destroyed
    assert(bdes == 1);  // instance of B was destroyed
    assert(ades == 1);  // A's destructor called as well obviously
    Unique!A cq = aq.move;  // use move to transfer ownership
    assert(!aq.valid);  // aq no longer holds value
    void consume(Unique!A ptr)
    {
        assert(ptr.valid);
    }   // ptr destroyed
    consume(cq.move);   // use move to transfer ownership
    assert(ades == 2);  // consume destroyed the resource held in cq
    assert(bdes == 1);
    assert(!cq.valid);
}
```
```d
auto uptr = Unique!int.make(5);
// you can convert uniqueptr to refcounted, but not vice versa
RefCounted!int rcptr = uptr.toRefCounted();
assert(!uptr.valid);
assert(rcptr.v == 5);
```
### RefCounted
```d
static int adec = 0;
class C { ~this() { adec++; } }
static int bdec = 0;
class D: C { ~this() { bdec++; }}
{
    RefCounted!C ag = RefCounted!C.make();
    {
        RefCounted!C aq = ag;   // copy constructor is not disabled
        assert(aq.valid && ag.valid);
        {
            RefCounted!C bq = RefCounted!D.make();  // upcast OK
        }   // bq destroyed
        assert(adec == 1);
        assert(bdec == 1);
    }   // aq out of scope, but it's resource is not destroyed
    // ag still holds the valid pointer
    assert(ag.valid);
    assert(adec == 1);
    assert(bdec == 1);
} // ag is the last owner, destructor called on A's instance
assert(adec == 2);
assert(bdec == 1);
```

### Delegate
```d
int sum = 0;
int[] arr = [3, 5, 1, 9, 4];
// Delegate!(T1, T2, T3, T4, ...) is a struct, that overloads opCall with signature
// T1 opCall(T2 p1, T3 p2, T4 p3, ...).First template parameter is the return type.
// Use `void` if it's a procedure.
void map(int[] arr, Delegate!(void, int) dlg)
{
    for (int i = 0; i < arr.length; i++)
        dlg(arr[i]);
}
// autodlg function deduces delegate type from it's arguments.
// It's first argument is allocator instance. Since we use allocation
// context with static allocator (Mallocator.instance), we don't
// need to pass it here.
// It's second argument is function pointer.
// The rest arguments are captured variables. Here, `sum` is captured
// by pointer.
// `sum` is bound to `s` function parameter. `x` is taken from
// the opCall of resulting Delegate.
// You are not limited to one captured parameter.
auto dlg = autodlg((int x, int* s) { *s += x; }, &sum);
map(arr, dlg);
assert(sum == 22);
```
```d
static int counter = 0;
// This call to autodlg constructs eponymous closure, that holds
// one int field. `int` type is deduced from `0`, not from `ref int ctr`.
// Function gets the reference `ref int ctr` to said
// int field of the closure.
Delegate!(void) dlg = autodlg((ref int ctr) { ctr++; counter = ctr; }, 0);
dlg();
dlg();
assert(counter == 2);
// Internally dlg holds a reference-counted instance of abstract
// class Closure. Body of this eponymous derived class contains the
// int field.
void consumeDlg(Delegate!(void) d) { d(); }    // the same closure
consumeDlg(dlg);
assert(counter == 3);
// OpEquals is overloaded to compare closure identity
auto dlg2 = dlg;
assert(dlg2 == dlg);
```
```d
import std.algorithm.comparison: equal;
import std.container.array: Array;

static string global_str;
class EventGenerator
{
    Array!(Delegate!(void, string)) handlers;
    void raise(string s)
    {
        foreach (dlg; handlers)
            dlg(s);
    }
}
class EventReciever
{
    string mystr;
    this(string custom_str) { mystr = custom_str; }
    void recieve(string evt)
    {
        global_str ~= mystr;
        global_str ~= evt;
    }
    ~this()
    {
        global_str ~= "D";
    }
}
{
    auto gen = RefCounted!EventGenerator.make;
    {
        auto rec1 = RefCounted!EventReciever.make("Fizz");
        auto rec2 = RefCounted!EventReciever.make("Buzz");
        gen.v.handlers ~= autodlg(
            (string s, typeof(rec1) rc){rc.v.recieve(s);}, rec1);
        gen.v.handlers ~= autodlg(
            (string s, typeof(rec2) rc){rc.v.recieve(s);}, rec2);
    }   // EventRecievers are still referenced from get.v.handlers array
    gen.v.raise("K");
    assert(equal(global_str, "FizzKBuzzK"));
}
// gen destroyed, array destructor destroys all closured.
// no more references to EventRecievers, their destructors run.
assert(equal(global_str, "FizzKBuzzKDD"));
```
```d
int x, y;
float z = 0.0f;
// autodlg is variadic, you can capture as many variables as you need.
Delegate!(float, float, float) ddlg =
    autodlg(
        (float a, float b, int x, int y, float z) => a + b + x + y + z,
        x, y, z);
assert(ddlg(1.0f, 2.0f) == 3.0f);
```
### Custom allocators
```d
import daii;

// If you want to use instantiated allocator:
import std.experimental.allocator.showcase;
alias AllocType = StackFront!(4096, Mallocator);
AllocType allocator;
// Note the AllocType*. Pointer to structure AllocType is used as
// allocator, not the structure itself.
alias StackFrontCtx = AllocationContext!(AllocType*, true);

// Construct primitives like this:
auto unq = StackFrontCtx.Unique!(int).make(&allocator, 5);
assert(unq.v == 5);
auto rcp = StackFrontCtx.RefCounted!(int).make(&allocator, 5);
assert(rcp.v == 5);
auto ddlg = StackFrontCtx.autodlg(&allocator, (int* x) { *x = 4; });
int k = 0;
ddlg(&k);
assert(k == 4);
```
