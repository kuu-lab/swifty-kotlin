// KUU-3807: an interface property default getter inherited by an enum entry
// used to fail at runtime (`KSWIFTK-RUNTIME-0001`) or link time
// (`Undefined symbols: __itable_impl_<id>`) — the itable-dispatched
// `.virtualCall` kept the receiver as a raw ordinal instead of the canonical
// tagged box the per-object itable lookup needs, and the enum's `.static`
// synthetic `entries` stub shadowed the interface property during bridge
// target selection.
interface I { val stuff: String get() = "OK" }
interface V { var v: String get() = "init"; set(u) {} }
interface Named { val name: String }
interface HasEntries { val entries: String get() = "OK" }

enum class E : I {
    X;
    fun test() = stuff
}

enum class E2 : I {
    A { override val stuff = "AX" },
    B;
    fun test() = stuff
}

enum class F : V { P, Q }
enum class N : Named { S }
enum class T : HasEntries { X }

class Plain(override val stuff: String = "plain") : I

fun main() {
    // Member-body read of the inherited default getter (the MRE).
    println(E.X.test())
    // Direct reads on the enum-typed entry and through values()/entries.
    println(E.X.stuff)
    println(E.values()[0].stuff)
    println(E.entries[0].stuff)
    // Interface-typed receiver dispatch.
    val i: I = E.X
    println(i.stuff)

    // An entry-body override must still win through every path.
    println(E2.A.test())
    println(E2.B.test())
    println(E2.A.stuff)
    println(E2.B.stuff)
    val i2: I = E2.A
    println(i2.stuff)

    // `var` interface properties dispatch both the getter and the setter.
    println(F.P.v)
    val fv: V = F.Q
    fv.v = "W"
    F.P.v = "W2"

    // KUU-3682 shape: compiler-provided `name` through an interface.
    val n: Named = N.S
    println(n.name)

    // An interface property sharing the synthetic `E.entries` stub's name:
    // interface-typed dispatch must reach the interface default getter, and
    // the registration must not reference the stub's bodiless accessor.
    val t: HasEntries = T.X
    println(t.entries)

    // A regular class implementing the same interfaces is unaffected.
    println(Plain().stuff)
}
