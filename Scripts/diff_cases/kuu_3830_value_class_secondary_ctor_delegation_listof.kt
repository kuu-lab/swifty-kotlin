// KUU-3830: a value-class secondary constructor whose delegation argument is
// built by a collection literal must still expose the delegated primary
// value. The lowering used to mistake the literal's internal
// `kk_array_set(array, 0, v)` store for the `this` field store and read the
// allocated box at offset 0 (the object header) instead of the underlying
// field — producing null.

@JvmInline
value class IC<T>(val value: List<T>) {
    constructor(value: T) : this(listOf(value))
}

@JvmInline
value class SC(val value: List<String>) {
    constructor(value: String) : this(listOf(value, value + "!"))
}

@JvmInline
value class IA(val value: IntArray) {
    constructor(value: Int) : this(intArrayOf(value, value + 1))
}

fun main() {
    println(IC("abc").value.singleOrNull())
    println(IC(listOf("x", "y")).value.size)
    println(SC("s").value)
    println(IA(5).value.toList())
}
