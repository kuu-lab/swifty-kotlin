// Regression: a newline between the context parameter prefix and `fun` used
// to split the contextual anonymous function into separate statements (KUU-4742).
fun main() {
    with("O") {
        val f = context(a: String)
        fun(y: String): String = a + y
        println(f("K"))
    }
}
