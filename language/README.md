# The Rolang language

Rolang is a statically typed, ahead-of-time compiled language for native
applications and compiler/tooling workloads. It uses LLVM for machine-code
optimization and a C runtime for its current operating-system and memory ABI.
The compiler, front-end services and standard library interfaces are written in
Rolang.

This guide covers the implemented language. The [project README](../README.md)
contains installation and compiler commands; the [std guide](../std/README.md)
lists libraries. Package management and a broader redesigned std are
[development work](../docs/roadmap.md).

## Design philosophy

### Automatic lifetimes with consistent reference semantics

Structs, enums, strings, closures and task handles are managed references.
Assignment shares an object. ARC handles normal ownership changes; a cycle
collector reclaims unreachable reference cycles. The same model applies to
ordinary data and compiler AST/HIR/MIR objects.

`let` controls rebinding, while field declarations control mutation. Explicit
copying is visible in source. Managed fields do not require manual retain,
release or free calls.

### Type-directed convenience and explicit boundaries

Local inference, contextual lambdas, generic inference, field shorthand and
tail expressions reduce repetition. Type checking still determines the types,
call targets and conversions before execution. Visibility, optional absence,
error propagation, async suspension and unsafe operations have explicit syntax.

### Compose behavior through protocols and extensions

Structs and payload enums model data. Protocols describe method/property
requirements; extensions add behavior and conformance. Generics specialize
concrete uses, while `any Protocol` supports runtime dispatch.

### Make control flow and failure inspectable

Exhaustive patterns describe all enum/optional cases. `Result<T, E>` carries
recoverable errors as data. `try` and postfix `?` propagate failure through
ordinary control flow, including required cleanup. Runtime panics handle
conditions such as integer division by zero and invalid vector indices.

### Optimize without changing observable semantics

Inlining, scalar replacement and ownership optimizations preserve aliases,
mutation, destruction and numerical behavior. LLVM and LTO optimize generated
code. Optimizations are implementation choices, not a promise that every
allocation disappears or that every workload has the same performance.

### Develop the language through its own compiler

The compiler exercises payload enums, generics, closures, protocols, collections,
text builders and explicit IDs. Building the compiler with a released compiler
keeps source-language changes connected to real compiler workloads.

## Features at a glance

| Area | Features |
| --- | --- |
| Types | Fixed-width integers, f32/f64, Bool, Void, tuples, optionals and function types |
| Data | Structs, payload enums, generic types, transparent aliases and default initialization |
| Functions | Methods, static methods, tail expressions, named/default arguments and closures |
| Control | if/while/for, ranges, switch statements/expressions, guards, patterns and defer |
| Abstraction | Generic constraints, protocols with inheritance and associated types, properties, extensions and existential dispatch |
| Failure | Optional binding/chaining/coalescing and Result/optional propagation |
| Text | Byte-oriented strings, raw/multiline literals, interpolation and builders |
| Lifetimes | ARC, synchronous cycle GC, release/trace hooks and shallow clone |
| Async | State machines, spawn, repeatable awaits, cancellation, timers and socket streams |
| Interop | Unsafe contexts, RawPtr, C declarations and layout/type built-ins |
| Modules | File/dotted imports, aliases, public exports and constants, re-exports and compiled .rlm |
| Compilation | Typed HIR/MIR, specialization, ownership passes, LLVM text, cache and LTO |

## Bindings, types and shared objects

`let` freezes a binding; `var` permits rebinding. A `let` reference can still
mutate `var` fields. A `let` field cannot be assigned after construction.
Plain assignment shares managed objects; it does not duplicate their contents.

<!-- example: bindings -->
~~~rolang
struct Counter { var value: i32; }

def main() -> i32 {
    let first = Counter { value: 1 };
    let second = first;
    second.value += 1;
    var total = 40;
    total += first.value;
    if total == 42 { return 0; }
    1
}
~~~

Primitive types are `i8/i16/i32/i64`, `u8/u16/u32/u64`, `f32/f64`, `Bool` and
`Void`. `RawPtr` is the low-level interop pointer type. Integer and floating
literal types can be supplied by context; ordinary inferred numeric literals
default to i32 and f64. The compiler permits supported integer widening;
other numeric conversions use `as`. Casts bind tighter than binary operators
and looser than prefix operators: `text.len() as i32 + 1` adds after the cast,
and `-x as i64` negates first.

Tuples store positional or named components. `[T]` denotes a vector type,
`[K: V]` denotes a dictionary type, and `(T) -> U` denotes a function type.
Annotations are needed where inference lacks sufficient context. Collection
literals take their element types from the expected variable, parameter, return
or field type, so `[]`, `[:]` and `[A { .. }, B { .. }]` for `[any P]` are
accepted there; an empty literal without such a type is an error. A value of
type `T` converts to every optional layer of `(T?)?`.

Declarations without an initializer produce the language's default state:
numeric zero, false, nil for optionals and an empty String. Managed aggregate
defaults are built by lowering; this does not expose uninitialized storage.

A module-level `let NAME = value;` (or `pub let` to export it) declares a
compile-time constant. Its value must be a constant expression made of literals,
operators, casts, ternaries and other constants, and its type must be a number,
Bool, String or an optional of one; each use evaluates the value in place, so
declaration order does not matter. Module-level `var` and other statements are
not allowed.

## Functions, named arguments and tail expressions

Functions use `def`. A final expression provides the return value; explicit
`return` remains available. Ordinary parameter names may be used as labels.
Default parameters are evaluated when omitted. Explicit external labels
declared by a signature must be respected, and arguments follow declaration order.
A labeled argument may skip parameters that have defaults:
`scale(5, offset: 1)` passes the default `factor`.

<!-- example: functions -->
~~~rolang
def scale(value: i32, factor: i32 = 2) -> i32 { value * factor }

def main() -> i32 {
    let first = scale(21);
    let second = scale(value: 14, factor: 3);
    if first == 42 && second == 42 { return 0; }
    1
}
~~~

Instance methods access `self`; `static def` methods are called on a type.
Function-value signatures also describe higher-order callbacks.

## Structs, field shorthand and copying

Struct literals name fields. An in-scope variable can supply a field with the
same name, and a field declared with a default (`var retries: i32 = 3;`) may be
omitted; the default is evaluated for each literal. Methods can mutate shared
`var` fields. Operator methods implement
source operators for user types: `__add__`, `__sub__`, `__mul__`, `__truediv__`,
`__mod__`, `__eq__`, `__ne__`, `__lt__`, `__le__`, `__gt__`, `__ge__`, `__and__`,
`__or__`, `__xor__`, `__lshift__` and `__rshift__` take the right operand;
`__neg__`, `__pos__` and `__invert__` implement unary `-`, `+` and `~`.
`x[i, j]` calls `__get__(i, j)` and `x[i, j] = v` calls `__set__(i, j, v)`;
`for` uses `__iter__` and `__next__`.

Built-in `.clone()` creates a separate outer object and retains managed fields:
it is a shallow copy. Nested reference fields continue to share their objects.
Types requiring a deep or resource-specific copy should expose their own API.

<!-- example: clone -->
~~~rolang
struct Counter { var value: i32; }
struct Box { var counter: Counter; var tag: i32; }

def main() -> i32 {
    let counter = Counter { value: 1 };
    let first = Box { counter, tag: 10 };
    let second = first.clone();
    second.tag = 20;
    second.counter.value = 42;
    if first.tag == 10 && first.counter.value == 42 { return 0; }
    1
}
~~~

## Enums, patterns and exhaustive switch

Enum cases can carry typed payloads. Patterns bind those payloads, match nested
optionals/enum cases, and may add `where` guards. Guarded or partial patterns do
not establish complete coverage. A value-producing switch needs compatible arm
types and exhaustive coverage; the input is evaluated once.

<!-- example: patterns -->
~~~rolang
enum Token { case number(i32); case empty; }

def read(token: Token) -> i32 {
    switch token {
        case .number(let n) where n > 0: n;
        case .number(let n): -n;
        case .empty: 0;
    }
}

def main() -> i32 {
    let name = switch Token.number(42) {
        case .number(let n): f"value={n}";
        case .empty: "empty";
    };
    if read(Token.number(-42)) == 42 && name.equals("value=42") { return 0; }
    1
}
~~~

Switch is available as a statement or expression. `if c { a } else { b }` is
also an expression, including `else if` chains, when each branch holds a single
expression. Enum construction can use `Type.case(...)` or a contextually typed
dot shorthand.

## Optionals, guards and propagation

`T?` represents a value or `nil`. `if let` binds a present value, `while let`
repeats while one is present, `guard let` requires one and keeps the binding
after the guard, `??` supplies a fallback, and `?.` performs optional chaining.
`x == nil` and `x != nil` test for a value, and `x == 5` compares a present value
(`nil` equals only `nil`, so two optionals are equal when both are nil). A guard's else branch must leave the
path. With a non-optional value these bindings need a refutable pattern, such as
`while let .item(value) = next()`.
Chaining covers fields, method calls and subscripts (`a?.items[0]`,
`a?.find(key)`); an optional member is not wrapped again, so `a?.next?.value`
has type `T?`. Chained calls must not return Void.

Postfix `?` in a function returning an optional unwraps a present value or
returns nil. It evaluates the operand once and runs pending synchronous defers.

<!-- example: optionals -->
~~~rolang
struct Item { var value: i32; }

def increment(value: i32?) -> i32? {
    let n = value?;
    n + 1
}

def read(value: Item?) -> i32 {
    guard let item = value else { return 0; }
    item.value
}

def main() -> i32 {
    let item: Item? = Item { value: 42 };
    if let unexpected = increment(nil) { return 2; }
    if (increment(41) ?? 0) == 42 && read(item) == 42
        && (item?.value ?? 0) == 42 { return 0; }
    1
}
~~~

## Result-based errors

`std.result` defines `Result<T, E>` with `ok(value: T)` and `err(error: E)`.
`try value` and `value?` unwrap success or return the error from the current
function. Success types may change between functions; the error type must match.
Custom two-case enums with the matching single-payload ok/err shape can also
participate. Library combinators include map, map_err, and_then and unwrap_or.

<!-- example: results -->
~~~rolang
import std.result

def read(valid: Bool) -> Result<i32, String> {
    if valid { return Result<i32, String>.ok(value: 21); }
    Result<i32, String>.err(error: "missing")
}

def twice(valid: Bool) -> Result<i32, String> {
    let n = try read(valid);
    Result<i32, String>.ok(value: n * 2)
}

def main() -> i32 {
    switch twice(true) {
        case .ok(let n): if n != 42 { return 1; }
        case .err(let error): return 2;
    }
    if is_err(twice(false)) { return 0; }
    3
}
~~~

Errors are typed values, and propagation follows explicit control flow.
Panics abort the process and are not caught through Result.

## Generics, aliases, protocols and extensions

Generic functions, structs, enums and methods specialize lazily for concrete
types. Inference uses arguments, callbacks, receiver types and return context.
Constraints check protocol requirements before code generation. Inside generic
code a value of a type parameter `T` is only a `T`, or an `any P` when `T` is
bounded by `P`; it does not convert to other types.

`typealias` is transparent, including generic aliases; it does not create a
distinct type or prevent mixing values of the underlying type. Recursive aliases
are rejected. A wrapper struct provides a separate nominal identity.

Protocols declare method or property requirements, can inherit requirements
(`protocol B: A, C`), and can be combined as generic constraints. A struct or
enum can declare conformances with its definition (`struct S: P, Q { ... }`),
which is equivalent to an empty `extension S: P, Q {}`. Extensions add methods or
conformance without adding stored fields; extension conformance satisfies
generic constraints on functions and types. A requirement may be a generic
method (`def map<U>(f: (i32) -> U) -> U;`); a witness declares the same number
of generic parameters, and calls through a constrained type parameter infer them
from the arguments.

`Self` in a requirement is the conforming type (`def beats(other: Self) -> Bool;`).
A requirement may be static (`static def make(n: i32) -> Self;`); generic code
calls it on the type parameter, `T.make(1)`. Static methods of builtin types are
called the same way: `i32.parse_or(text, 0)`.
Such members are used through a bounded type parameter, not through `any P`.
Requirements named after operator methods make the operators available on a
bounded parameter: the implicitly imported `Equatable` (`__eq__`) and `Comparable`
(`__lt__`, inheriting Equatable) let generic code write `a == b`, `a != b`,
`a < b`, `a > b`, `a <= b` and `a >= b`, the last three and `!=` derived from
`__lt__` and `__eq__`. Numbers satisfy them with their built-in operators, Bool
is Equatable, and String conforms through its methods; a struct conforms by
defining `__eq__` and `__lt__`, after which all six operators also work on it
directly. Vec uses them for `sort()`, `sorted()`, `min()`, `max()`,
`binary_search()`, `contains()` and `index_of()`. `Hashable` (`hash() -> u64` plus
Equatable) makes struct values usable as Dict keys and Set elements by
content.

Declaring `Equatable`, `Hashable`, `Comparable`, `Encodable`, `Decodable` or
`Codable` on a struct or enum without defining the methods derives them from
the fields (or cases): equality and hashing of every field, field-by-field
ordering, and JSON encoding through std.json. Methods the type defines itself
are kept. Errors in derived code point at the field involved.

A method of a generic type may bound the type's parameters with `where`
(`def total_area() -> i32 where T: Shape`); the body may use T as a Shape and each
call checks the receiver's type argument. Extensions of generic types name the
parameters after `extension`: `extension<T> Box<T> { ... }`.

A protocol may declare associated types (`associatedtype Item;`, or primary
associated types in its header: `protocol Container<Item> { ... }`) and use them in
its requirements. Each conformance infers them from its members, e.g. a
`def first() -> i32` witness makes `Item` i32; a generic conforming type infers
them per type argument. A generic parameter `C: Container` names them as `C.Item`,
and `where C.Item == i32` requires a specific type, which the body may then use as
i32. Generic calls check the callee's bounds and `where` constraints.
`Container<i32>` fixes the primary associated types: as a bound (`C: Container<i32>`)
it means `C: Container where C.Item == i32`, in a conformance (`struct S:
Container<i32>`) the members must agree with it, and `any Container<i32>` makes
every member usable through the existential. A plain `any Container` only allows
members whose signatures do not use unfixed associated types. A type has one
conformance per protocol, so it cannot conform to both `P<i32>` and `P<String>`.

<!-- example: associated -->
~~~rolang
protocol Container {
    associatedtype Item;
    def get(index: i32) -> Item;
    def size() -> i32;
}
struct Stack<T>: Container {
    var items: [T];
    def get(index: i32) -> T { self.items[index] }
    def size() -> i32 { self.items.len() as i32 }
}

let FIRST = 0;

def last<C: Container>(c: C) -> C.Item { c.get(c.size() - 1) }
def total<C: Container>(c: C) -> i32 where C.Item == i32 {
    var sum = 0;
    for index in FIRST..<c.size() { sum += c.get(index); }
    sum
}

def main() -> i32 {
    let numbers = Stack<i32> { items: [10, 30, 2] };
    let words = Stack<String> { items: ["ro", "lang"] };
    if total(numbers) == 42 && last(words) == "lang" && last(numbers) == 2 { return 0; }
    1
}
~~~

`any P` boxes a conforming object with its witness table for
dynamic dispatch.

<!-- example: protocols -->
~~~rolang
protocol Readable { def read() -> i32; }
struct Item { var value: i32; }
extension Item: Readable { def read() -> i32 { self.value } }
struct Box<T> { var value: T; def get() -> T { self.value } }
typealias Wrapped<T> = Box<T>;

def read_static<T: Readable>(value: T) -> i32 { value.read() }
def read_dynamic(value: any Readable) -> i32 { value.read() }

def main() -> i32 {
    let item = Item { value: 42 };
    let boxed = Wrapped<Item> { value: item };
    if read_static(boxed.get()) == 42 && read_dynamic(item) == 42 { return 0; }
    1
}
~~~

Generic calls resolve concrete methods statically; existential calls use the
witness table. Use each representation according to the data being stored and
the dispatch behavior needed.

## Closures and higher-order functions

Function values can be stored in fields, passed to functions and returned.
A closure is written `(params) -> ReturnType { body }`. Parameter types may be
omitted when a contextual function type supplies them, and the return type may be
omitted to infer it from the body.
Closures capture variables by reference: a `var` (including `var` bindings in
switch, for and if-let patterns) that a closure captures and that is reassigned
(inside or outside the closure) is shared, so updates on either side are visible
to the other and survive after the enclosing function returns. Such a variable
lives in a managed cell; other captures are copied into the closure object,
which is equivalent because they never change. Captured managed objects remain
alive while owned by the closure.

<!-- example: closures -->
~~~rolang
def make_adder(base: i32) -> (i32) -> i32 {
    (n: i32) -> { base + n }
}
def make_counter() -> () -> i32 {
    var count = 0;
    () -> { count += 1; count }
}
def apply(f: (i32) -> i32, value: i32) -> i32 { f(value) }
def twice(n: i32) -> i32 { n * 2 }

def main() -> i32 {
    let add = make_adder(40);
    let contextual: (i32) -> i32 = (n) -> { n + 1 };
    let next = make_counter();
    next();
    var total = 40;
    let bump = () -> { total += next(); };
    bump();
    if add(2) == 42 && apply(twice, 21) == 42 && contextual(41) == 42 && total == 42 { return 0; }
    1
}
~~~

Further forms: `(n: i32) -> i32 { n + 1 }` declares every type,
`values.map((x) -> { x * 2 })` infers them, `() -> { counter.tick(); }` takes no
arguments, and `((a, b)) -> { a + b }` destructures a tuple argument. A `{` in
expression position is not a closure.
Named synchronous, non-generic safe functions can be adapted to function values,
and `value.method` without a call is a closure bound to that receiver, which is
evaluated once (`value?.method` gives an optional closure).
Use wrappers for generic/unsafe functions. Async functions are values too:
`let f = fetch` or `(id: i32) async -> String { ... }` has type `(i32) async ->
String`; calling it inside async code awaits the call, and `spawn f(1)` starts it
as a Task. Dynamic dispatch of async protocol requirements is not supported.

## Collections, tuples, ranges and iteration

`Vec<T>`, `Dict<K, V>` and `String` are imported implicitly for ordinary source
files, together with the range foundation. Nonempty literals use their elements
and context to infer types. Tuples support destructuring, including nested
bindings and discarded components.

`..<` excludes the upper range bound; `...` includes it. Bounds are i32;
descending ranges are empty. Vector/string slices clamp bounds and return
copies; managed vector elements stay shared, and string indices count bytes.
Bounds may be omitted: `v[..<3]`, `v[...2]`, `v[2...]` and `v[...]` (an open upper
bound runs to the i32 maximum, which slicing clamps). Assigning to a Vec slice,
`v[1..<3] = [x, y, z]`, replaces that range with values of any length.

<!-- example: iteration -->
~~~rolang
import std.iterator

def main() -> i32 {
    let values = [1, 2, 3, 4];
    let (base, _) = (30, 99);
    let selected = values.iter().filter((n) -> { n > 1 }).map((n) -> { n * 2 }).collect();
    let first = selected[0..<2];
    var sum = base;
    for value in first { sum += value; }
    let counts = ["answer": sum + 2];
    if (counts["answer"] ?? 0) == 42 { return 0; }
    1
}
~~~

`Dict<K, V>.new()` and `Set<T>.new()` create empty collections (as do `[:]`
and annotated literals); String keys compare by content and other keys by their
bytes. Dict preserves insertion order; get/remove return optional values. keys/values/
entries produce snapshots owning their references. Structural mutation during
live iteration is not supported. `HashMap<K, V>` accepts explicit hash/equality
callbacks for structural keys.

`Iter<T>` is lazy and single-pass. Aliases share its cursor; its first nil ends
iteration permanently. map/filter/take/zip/enumerate compose adapters, and
collect/fold consume them. Optionals inside an iterator are distinct from its
end marker.

## Text, interpolation and compiler-writing utilities

String literals contain UTF-8 bytes, including embedded NUL. `==`, `!=`, `<`,
`<=`, `>` and `>=` compare strings byte-wise. len, char_at, byte_at, substring
and slice count bytes; char classification is ASCII. Unicode views decode the
bytes: `scalars()`/`scalar_count()` give code points (each invalid byte reads as
U+FFFD), `graphemes()`/`grapheme_count()` give extended grapheme clusters
(user-perceived characters, Unicode 16 UAX #29), `is_valid_utf8()` checks the
encoding and `String.from_scalar(cp)` encodes one code point.

Ordinary quoted literals process escapes, including `\u{1F600}` for any Unicode
scalar (also in character literals). Raw literals preserve backslashes;
triple-quoted literals preserve newlines and indentation. Explicit `f"..."`
interpolation evaluates fields once from left to right through to_string.
`{{` and `}}` emit literal braces. `{value:spec}` formats with a
specification `[[fill]align][sign][#][0][width][.precision][type]`, as in
Python: `{pi:.2}` → `3.14`, `{n:08}`, `{n:#x}` → `0xff`, `{name:>10}`,
`{ratio:.1%}`. Integer types are d x X o b, number types f e %; precision is
decimal places for numbers and a maximum length for text. The value's
`format(spec)` method does the work; types without one format their to_string.
An invalid specification is a compile-time error. Floats print with the fewest
digits that read back exactly (`0.1 + 0.2` is `0.30000000000000004`).

<!-- example: text -->
~~~rolang
import std.string_builder
import std.interner

def main() -> i32 {
    let path = r"C:\compiler\cache";
    let text = "hé\0llo";
    let builder = StringBuilder.new();
    builder.append(f"{{{42}}}");
    let names = StringInterner.new();
    let first = names.intern("token");
    if names.intern("token") == first && builder.to_string().equals("{42}")
        && text.len() == 7 && text.byte_at(3) == 0 && path.contains(r"\") { return 0; }
    1
}
~~~

StringBuilder grows a reusable byte buffer and returns independent snapshots.
StringInterner provides stable IDs scoped to one interner. CodeWriter adds
indentation-aware source output; c_quote escapes generated C byte strings.
Interpolation is formatting, so code generators must use the appropriate
escaping function when embedding data into another language.

## Control flow, defer and cleanup

if, while and for use lexical scopes. break/continue exit the corresponding
loop path. defer runs in reverse registration order on normal synchronous
scope exits, returns and supported propagation paths.

<!-- example: defer -->
~~~rolang
struct Counter { var value: i32; }

def sum(counter: Counter) -> i32 {
    defer { counter.value += 1; }
    var total = 0;
    for n in 0..<10 {
        if n == 3 { continue; }
        if n == 8 { break; }
        total += n;
    }
    total
}
def main() -> i32 {
    let counter = Counter { value: 0 };
    if sum(counter) == 25 && counter.value == 1 { return 0; }
    1
}
~~~

Suspended async cancellation has different cleanup behavior, described below.

## Memory management and resource hooks

Managed structs/enums have reference semantics and normally allocate on the
heap. Primitive values remain ordinary scalar values. The compiler inserts
ownership operations and the runtime releases managed fields. Scalar replacement
may remove a nonescaping aggregate allocation while preserving its behavior.

An instance `__release__() -> Void` hook can release external resources before
managed fields are released. The ABI requires the exact method shape; it is
validated even for types that are never allocated. A static
`__gc_trace__(payload: RawPtr, callback: RawPtr, context: RawPtr) -> Void` hook
lets runtime-backed containers expose references to the cycle collector.
These hooks are runtime integration contracts, not ordinary cleanup calls.

The cycle collector uses synchronous generational trial deletion. It handles
unreachable reference cycles, including supported closure/task/container graphs.
Collection can pause execution, and cyclic resources can be destroyed later
than acyclic ones. Release hooks run before fields are reclaimed, and the runtime
accounts for objects retained again during destruction.

Compiler/runtime optimizations include:

- Lifetime/CFG-aware retain-release removal and borrowing of safe read-only uses.
- Type-graph analysis excluding proven acyclic types from cycle-GC candidates.
- Per-type field cleanup and enum-tag filtering.
- Pool allocation for small objects and no-init allocation when every live field
  is immediately initialized.
- Inlining/scalar replacement that preserves escapes, aliases and custom hooks.

These affect implementation cost; source reference semantics remain unchanged.
Panics such as division by zero, invalid vector indices and cancelled-task result
awaits abort the process.

## Async, tasks, cancellation and socket I/O

Async functions lower to heap frames and resume state machines.
One cooperative scheduler runs ready work; timers and POSIX poll readiness
suspend tasks without busy-spinning. CPU-bound work must yield explicitly
to let other tasks run.

<!-- example: async -->
~~~rolang
import std.task

def work(n: i32) async -> i32 {
    await yield_now();
    n * 2
}

def main() async -> i32 {
    let task = spawn work(21);
    let first = await task;
    let second = await task;
    if first == 42 && second == 42 && task.done() { return 0; }
    1
}
~~~

An ordinary async call awaits its child; spawn returns a Task immediately.
Arguments are evaluated at spawn time; execution starts when the scheduler
gets control. Task copies share one handle and completed results are repeatably
awaitable. Spawn is also allowed in synchronous code.

| Operation | Behavior |
| --- | --- |
| `await task` | Obtain its result; a cancelled task panics |
| `task.done()/cancelled()` | Inspect completion/cancellation |
| `task.cancel()` | Cancel unfinished work between resume steps |
| `await task.wait()` | Wait for completion status without unwrapping a result |
| `task.wait_blocking()` | Synchronous scheduler bridge |
| `await sleep(ms)/yield_now()` | Suspend on a timer/yield point |

Dropping the final task reference cancels unfinished work. Cancellation releases
the suspended frame, retained values and applicable implicit child dependencies;
it does not preempt executing code or reverse completed side effects.
**Cancellation discards pending defers in the suspended continuation.**
Resources requiring cancellation cleanup should be owned by managed objects
with release hooks. Returning from main cancels remaining tasks.
Self-await and cyclic task dependencies panic.

std.async_io supplies AsyncStream, AsyncPipe and AsyncListener:
reads/writes and connect/accept are async; local socket pairs and TCP numeric
IPv4/IPv6 addresses are supported. I/O returns Result values with POSIX errno
errors. Read boundaries are byte boundaries; an empty successful read indicates
EOF or a zero-length request. A failed write may already have sent a prefix.
Use one reader/writer per stream when ordering matters.

Current filesystem/console I/O is blocking. DNS, TLS and asynchronous regular-file
I/O are not implemented. Task timers/socket readiness require the POSIX runtime.
See the [async API guide](async.md).

## Unsafe interop and runtime type operations

C functions use `extern "C" def`. Calling external or unsafe functions and
performing RawPtr operations require an unsafe context. That context does not
implicitly extend into closures. Explicit casts and ownership transfers at
FFI boundaries must match the C/runtime representation. `x as RawPtr` is the
address of the variable `x`, as C out-parameters expect; `p as T` for a struct or
other managed type reads the reference stored at `p`, so the two round-trip.
Integer casts of a RawPtr convert the address itself.

<!-- example: unsafe -->
~~~rolang
extern "C" def rt_gc_collect();

def main() -> i32 {
    unsafe { rt_gc_collect(); }
    0
}
~~~

Layout/type built-ins include size_of, align_of and type_id_of. Runtime casts
use the compiler's concrete type identities and descriptors; optional cast
forms represent a failed check as nil. ABI types and runtime IDs must not be
invented by callers or treated as portable serialized identities.

## Modules, visibility and compiled libraries

Each source file is a module. Quoted imports resolve relative files and include
roots; dotted imports such as `import std.io` resolve module paths. Canonical
paths distinguish same-named modules in different directories.

Declarations and fields need `pub` to be available to other modules. Imports
may use aliases; `pub import` re-exports public declarations. Source dependency
cycles are rejected. -I adds roots and --stdlib selects a root containing std/.

`.rlm` bundles source/generic metadata, native objects or LLVM bitcode,
dependency identities and checksums. Consumers can instantiate generics with
their own types after library source is removed. ABI/target/checksum mismatches
are errors. Source and compiled module behavior share visibility and type
identity rules. The Rolang module format is `rolang-module-1` with the
`rolang-abi-1` ABI tag.

See [compiled artifacts and CLI](../docs/compiler.md) for examples and resource
layout. Workspace manifests/package resolution are planned tooling, separate
from the implemented source import mechanism.

## Compiler design and numerical behavior

The pipeline is:

~~~text
Source/import graph
  → typed AST and symbols
  → typed HIR
  → generic specialization
  → CFG MIR and closure lifting
  → output-parameter initialization cleanup
  → async lowering and ownership/optimization passes
  → LLVM IR text
  → clang object/assembly generation
  → native linking or full/ThinLTO
~~~

AST, HIR and MIR use separate stable node identities within their arenas.
Typed side tables carry resolution/checking/lowering information. Ordinary
in-process IDs are different from the stable recursive identities used in
compiled module ABI records.

O0 performs required lowering and ownership work. O1 adds ARC optimization;
O2/O3 also permit MIR inlining and scalar replacement. Full/ThinLTO can optimize
Rolang and C runtime bitcode together.

Integer division handles zero and the signed minimum/-1 case; shifts mask their
counts. Floating-to-integer conversion uses saturating lowering. Mixed floating
comparisons use proper widening. The f64 remainder fast path is guarded and
falls back to libm fmod when the proof does not hold; fast-math is not enabled
for this path.

Selected Vec/Dict scalar access and String byte/ASCII access have direct LLVM
fast paths. Bounds, null behavior and managed ownership are preserved. Aggregate
or managed cases use runtime accessors when direct lowering is not applicable.

## Standard library and current development scope

The bundled library covers collections, byte-oriented text/builders, Optional/
Result combinators, math, files/paths/processes, task control, async socket I/O,
hashing and test assertions. [All 29 modules](../std/README.md) are listed with
their current responsibilities.

New library design will establish explicit error/ownership/encoding/platform
contracts before expanding JSON/TOML, time, randomness, networking and
serialization. Native project management, dependencies, registries and LSP are
tracked in the roadmap. The initial validated execution platform is macOS arm64;
broader target support requires platform-specific compilation and execution.
