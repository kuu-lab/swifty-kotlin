// KUU-3202: an enum that satisfies an interface `val name` through the
// compiler-provided Enum.name member must still emit the itable getter body
// (previously the bridge called an undefined __itable_impl_<symbol>).
interface Named {
    val name: String
}

enum class E : Named {
    OK
}

fun describe(named: Named): String = named.name

fun main() {
    println(E.OK.name)
    println(describe(E.OK))
    println(E.OK.ordinal)
}
