// Enums nested under objects (not just classes) must get their
// $enumConstructorProperty$ storage helpers emitted; previously the
// synthesis walk only descended through classDecl.nestedClasses, so an
// enum nested in an object left its member bodies calling an unresolved
// helper (KUU-3544 follow-up).
object Outer {
    enum class E(val tag: String) {
        A("a"),
        B("b");

        fun test() = tag
    }

    // Same shape, but with a user `entries` member: inside the enum body it
    // must still resolve to the instance property, while the qualified
    // `E.entries` read resolves the synthetic EnumEntries list.
    enum class WithEntries(val entries: String) {
        E("OK");

        fun test() = entries
    }
}

fun main() {
    println(Outer.E.A.test())
    println(Outer.E.B.test())
    println(Outer.E.entries)
    println(Outer.WithEntries.E.test())
    println(Outer.WithEntries.entries)
}
