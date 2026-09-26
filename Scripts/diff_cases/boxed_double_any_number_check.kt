// A Double/Float/Long/Int held in an Any/Any? slot must still answer `is
// Number`, a constant-branch `==` against a Double/Float literal in `when`,
// and `in`/`contains` against a List<Double> -- all three go through
// different runtime paths than the same operation on a statically-typed
// primitive.
fun describe(x: Any?): String = when (x) {
    null -> "null"
    1, 2 -> "small int"
    is Int -> "int"
    in listOf(3.0, 4.0) -> "listed double"
    else -> "other"
}

fun main() {
    val x: Any = 3.0
    println(when (x) { is Number -> "num ${x.toInt()}"; else -> "?" })
    println(when (x) { 3.0 -> "three"; else -> "no" })

    val f: Any = 3.0f
    println(when (f) { is Number -> "num ${f.toInt()}"; else -> "?" })
    println(when (f) { 3.0f -> "three"; else -> "no" })

    val y: Any = 3
    println(when (y) { 3.0 -> "double3"; 3 -> "int3"; else -> "no" })

    println(describe(3.0))
    println(describe(5.0))

    println((3.0 as Any) is Number)
    println((3.0f as Any) is Number)
    println((3L as Any) is Number)
    println((3 as Any) is Number)
    println((3u as Any) is Number)
    println(('c' as Any) is Number)
    println((3 as Any) is Comparable<*>)

    println((3.0 as Any) == 3.0)
    println(listOf<Any>(3.0).contains(3.0))
    println(listOf(3.0, 4.0).contains(x as Any?))
}
