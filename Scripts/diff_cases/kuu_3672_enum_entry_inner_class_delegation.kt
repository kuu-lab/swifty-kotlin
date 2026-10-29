// KUU-3672: a class nested inside an enum entry's anonymous class body never
// got delegation storage (`$delegate_I` field / forwarders), so
// `inner class Inner : IFoo by FOO` produced an uninitialized itable slot and
// `z.foo()` fell through to null. Separately, an enum entry used as a `by`
// delegate expression (even from a top-level class, `D : IFoo by Test.BAR`)
// stored the raw ordinal into the object field — ordinal 0 is a null handle —
// instead of the tagged enum box. JetBrains
// enum/enumEntryReferenceFromInnerClassConstructor3.kt + sibling variants.

interface IFoo {
    fun foo(): String
}

interface IBar {
    fun bar(): String
}

enum class Test : IFoo, IBar {
    FOO {
        // FOO referenced from inner class constructor with initialized 'this',
        // in delegate initializer.
        inner class Inner : IFoo by FOO

        val z = Inner()

        override fun foo() = "OK"

        override fun bar() = z.foo()
    },
    ;
}

enum class Other : IFoo {
    A { override fun foo() = "A-OK" },
    B { override fun foo() = "B-OK" },
    ;
}

// The same raw-ordinal store broke delegation to an enum entry from an
// ordinary class field too.
class Delegator : IFoo by Other.B

// ... and from another enum's class-level delegation (per-entry side slot).
enum class Deleg : IFoo by Other.A { X, Y }

fun main() {
    println(Test.FOO.bar())
    println(Test.FOO.foo())
    println(Delegator().foo())
    println(Deleg.X.foo())
    println(Deleg.Y.foo())
}
