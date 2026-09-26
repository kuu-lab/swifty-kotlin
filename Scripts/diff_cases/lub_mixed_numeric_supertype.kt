// TypeSystem.lub() over 2+ non-identical, non-KClass bounds (here Int and
// Long, neither a subtype of the other) fell back straight to Any instead of
// walking to their nearest common ancestor kotlin.Number, so T was inferred
// as Any and the assignment below failed with "Conflicting bounds for type
// variable: inferred Any is not a subtype of Number".
fun <T> pick(a: T, b: T): T = a

fun main() {
    val n: Number = pick(1, 2L)
    println(n.toDouble())
}
