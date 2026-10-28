// KUU-3146: a `null` literal safe call resolves to the single nullable
// `Any.toString`/`hashCode`/`equals` member. `null` is typed `Nothing?`, a
// bottom type that is nominally a subtype of every receiver, so without the
// narrowing the call collected unrelated `toString` extensions
// (UIntRange.toString, Instant.toString, ...) and reported an ambiguous
// overload. Mirrors JetBrains fixture boxingOptimization/kt5493.

fun box(): String {
    null?.toString()
    return "OK"
}

fun main() {
    println(box())
    println(null?.toString())
    println(null?.hashCode())
    println(null?.equals(null))
    val s: String? = null
    println(s?.toString())
    val a: Any? = null
    println(a?.toString())
    val n: Nothing? = null
    println(n?.toString())
}
