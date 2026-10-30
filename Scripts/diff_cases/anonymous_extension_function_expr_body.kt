// Regression for KUU-3842: anonymous extension function expressions with
// expression bodies `fun T.(a): R = expr` used to be rejected with
// KSWIFTK-PARSE-0001 "Expected '{' for anonymous function body."
// (fixed by #12121; this case pins the behaviour end-to-end).
class Nested(val v: String)

fun main() {
    println("O".(fun String.(y: String): String = this + y)("K"))
    val f: String.(String) -> String = fun String.(y: String): String = this + y
    println("A".f("B"))
    println(Nested("N").(fun Nested.(s: String): String = v + s)("!"))
}
