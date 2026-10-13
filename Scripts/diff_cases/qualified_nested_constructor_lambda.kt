import A.B

class A { class B(val xs: List<String>, val f: (String) -> String) }
class Single { class B(val f: (String) -> String) }
class Plain { class B(val xs: List<String>) }
class Generic { class B<T : Any>(val xs: List<T>, val f: (String) -> T) }

fun main() {
    println(A.B(listOf("a"), { it }).xs.size)
    println(A.B(listOf("a"), { s: String -> s }).f("explicit"))
    val fn: (String) -> String = { it }
    println(A.B(listOf("a"), fn).f("variable"))
    println(B(listOf("a"), { it }).f("import"))
    println(Plain.B(listOf("a")).xs.size)
    println(Single.B({ it }).f("single"))
    println(A.B(f = { it }, xs = listOf("a")).f("named"))
    println(A.B(listOf("a")) { it }.f("trailing"))
    println(Generic.B(listOf("a"), { it }).f("inferred"))
    println(Generic.B<String>(listOf("a"), { it }).f("type-argument"))
    val expected: Generic.B<String> = Generic.B(listOf("a"), { it })
    println(expected.f("expected"))
}
