// KUU-3891: the `.static` synthetic `E.entries` EnumEntries stub is a
// classifier-scope member, not an instance member. `E.X.entries` and an
// unqualified `entries` inside the enum body must resolve the inherited
// interface member, while the qualified `E.entries` keeps returning
// EnumEntries — and on a plain enum the unqualified read still reaches the
// enum's own static scope.
interface I { val entries: String get() = "OK" }

enum class E : I {
    X;
    fun test() = entries
    fun testThis() = this.entries
}

enum class Plain { P }

enum class WithVal(val entries: Int) {
    A(5);
    fun test() = entries
}

class Outer {
    val entries = "outer"
    enum class Nested {
        N;
        fun test() = entries
    }
    fun run() = Nested.N.test()
}

fun main() {
    // Instance-typed receivers resolve the inherited interface member —
    // the `.static` stub is not an instance member.
    println(E.X.test())
    println(E.X.testThis())
    println(E.X.entries)
    fun show(e: E) = e.entries
    println(show(E.X))
    val i: I = E.X
    println(i.entries)

    // The qualified class-name read still returns the EnumEntries list.
    println(E.entries[0])
    println(Plain.entries[0])

    // Plain enum: the unqualified read inside the body resolves through
    // the enum's own classifier static scope.
    println(Plain.P.name)
    println(E.values()[0].entries)

    // A user-declared instance `val entries` keeps winning instance lookups;
    // the qualified `WithVal.entries` still reads the synthetic stub.
    println(WithVal.A.entries)
    println(WithVal.A.test())
    println(WithVal.entries[0])

    // An enclosing classifier's static scope interleaves into the receiver
    // tower: the nested enum's static `entries` outranks the outer class's
    // instance member.
    println(Outer().run())
}
