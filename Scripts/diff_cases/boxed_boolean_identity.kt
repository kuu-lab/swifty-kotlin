// KUU-2093: independently boxed Booleans share the JVM singleton cache.
fun box(b: Boolean): Any = b
fun nullableBox(b: Boolean?): Any? = b
fun <T> genericBox(value: T): Any? = value

fun main() {
    println(box(true) === box(true))
    println(box(false) === box(false))
    println(box(true) === box(false))
    println(box(true) !== box(false))

    val nullableTrue: Boolean? = true
    val nullableFalse: Boolean? = false
    println(nullableBox(nullableTrue) === box(true))
    println(nullableBox(nullableFalse) === box(false))
    println(nullableBox(null) === null)
    println(nullableBox(null) === box(false))

    println(genericBox(true) === box(true))
    println(genericBox(false) === box(false))

    val values = listOf<Any>(true, false, true, false)
    println(values[0] === values[2])
    println(values[1] === values[3])
    println(values[0] === values[1])
    println(box(true) as Boolean)
    println(box(false) as Boolean)
}
