// BUG-185: `?:` must not evaluate its fallback when the left operand is
// non-null. The strict lowering evaluated both sides, so a `return`/`throw`/
// `continue` fallback always fired and side effects always ran.
class Box(val a: Int) {
    override fun equals(other: Any?): Boolean {
        val o = other as? Box ?: return false
        return a == o.a
    }

    override fun hashCode(): Int = a
}

fun firstOr(x: Int?): Int {
    val v = x ?: return -1
    return v + 1
}

fun labelOr(s: String?): String {
    val v = s ?: return "none"
    return "got $v"
}

fun orThrow(x: Int?): Int {
    val v = x ?: throw IllegalStateException("missing")
    return v
}

fun firstNonNull(values: List<Int?>): Int {
    for (value in values) {
        val v = value ?: continue
        return v
    }
    return -1
}

var sideEffects = 0

fun fallback(): Int {
    sideEffects += 1
    return 0
}

fun main() {
    println(firstOr(5))
    println(firstOr(null))
    println(labelOr("hi"))
    println(labelOr(null))
    println(orThrow(7))
    try {
        orThrow(null)
    } catch (e: IllegalStateException) {
        println("caught ${e.message}")
    }
    println(firstNonNull(listOf(null, null, 3, 4)))
    println(firstNonNull(listOf(null)))

    val present: Int? = 42
    println(present ?: fallback())
    val absent: Int? = null
    println(absent ?: fallback())
    println(sideEffects)

    println(Box(1) == Box(1))
    println(Box(1) == Box(2))
    println(Box(1).equals("no"))
    println(Box(1).equals(null))
}
