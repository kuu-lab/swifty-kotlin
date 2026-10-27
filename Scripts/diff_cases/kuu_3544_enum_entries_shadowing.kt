// KUU-3544: user-declared `entries` members must keep Kotlin's shadowing
// priority over the synthetic `Enum.entries` EnumEntries property.

// Companion `val entries` shadows on the companion only: `E0.entries` still
// resolves the synthetic EnumEntries list while `E0.Companion.entries`
// reaches the user declaration.
enum class E0 { A1; companion object { val entries = "OK" } }

// The enum's own `entries` shadows an enclosing object's same-named member
// for unqualified reads inside the enum body.
object Shadowing {
    val entries = "OK"
    enum class E0 { E; fun test() = entries }
}

// A nested `object entries` keeps member-call resolution on the object.
enum class E01 {; object entries { override fun toString() = "OK" } }

// A constructor `val entries` keeps instance-property priority in the enum
// body while the qualified `E02.entries` read stays synthetic.
enum class E02(val entries: String) { E("OK"); fun test() = entries }

enum class Plain { X, Y }

fun main() {
    println(E0.entries)
    println(E0.Companion.entries)
    println(Shadowing.E0.E.test())
    println(E01.entries.toString())
    println(E02.E.test())
    println(E02.entries)
    println(Plain.entries)
}
