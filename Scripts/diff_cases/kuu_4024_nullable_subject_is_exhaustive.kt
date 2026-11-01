// KUU-4024: a `when` over a nullable subject is exhaustive when the
// positive `is` checks cover the non-null domain and a `null` branch
// covers the rest (`is T` + `null` covers `T?`). A covering check alone
// (`is X` with S <: X) also suffices on a non-null subject, and a
// nullable check (`is T?`) covers the null part on its own.

sealed class S {
    data object A : S()
    class B : S()
}

enum class E { X, Y }

open class C
interface I

fun <T> genericT(x: T?): String = when (x) {
    is Any -> "any"
    null -> "null"
}

fun <T : Any> nonNullBound(x: T): String = when (x) {
    is Any -> "any"
}

fun <T : Int?> intBound(x: T): String = when (x) {
    is Int -> "int"
    null -> "null"
}

fun main() {
    val n: Int? = 5
    val s: String? = "x"
    val e: E? = E.X
    val b: Boolean? = true
    val ss: S? = S.A
    val a: Any? = 1
    val nn: Int? = null
    println(when (n) { is Int -> "int"; null -> "null" })
    println(when (nn) { is Int -> "int"; null -> "null" })
    println(when (s) { is String -> "str"; null -> "null" })
    println(when (e) { is E -> "enum"; null -> "null" })
    println(when (b) { is Boolean -> "bool"; null -> "null" })
    println(when (ss) { is S -> "sealed"; null -> "null" })
    println(when (a) { is Any -> "any"; null -> "null" })
    // A supertype check also covers the non-null domain.
    println(when (n) { is Number -> "num"; null -> "null" })
    // `is T?` covers the whole `T?` domain (null included) by itself.
    println(when (n) { is Int? -> "q" })
    // Non-null subject: a covering check alone is exhaustive.
    val i: Int = 5
    val c: C = C()
    val ii: I = object : I {}
    println(when (i) { is Int -> "int" })
    println(when (c) { is C -> "c" })
    println(when (ii) { is I -> "i" })
    // Generic subjects.
    println(genericT(4))
    println(genericT<Int?>(null))
    println(nonNullBound(3))
    println(intBound(1))
    println(intBound<Int?>(null))
}
