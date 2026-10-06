fun checkIdentity(array: Any, contents: String) {
    val identity = array.toString()
    println(identity.contains("@"))
    println(identity != contents)
    println(listOf(array).toString() == "[" + identity + "]")
    println(setOf(array).toString() == "[" + identity + "]")
    println(mapOf("array" to array).toString() == "{array=" + identity + "}")
    println("$array" == identity)
    println("array=" + array == "array=" + identity)
}

fun main() {
    val first = arrayOf(1, 2)
    val second = arrayOf(3)
    checkIdentity(first, first.contentToString())
    checkIdentity(arrayOf("x"), "[x]")
    checkIdentity(emptyArray<Int>(), "[]")
    checkIdentity(arrayOfNulls<String>(2), "[null, null]")

    val nested = arrayOf(first, second)
    println(nested.contentToString() == "[" + first.toString() + ", " + second.toString() + "]")
    println(nested.contentDeepToString())
    println(nested.contentToString() != nested.contentDeepToString())
    println(listOf(first).toString() == "[" + first.toString() + "]")

    checkIdentity(booleanArrayOf(true, false), "[true, false]")
    checkIdentity(byteArrayOf(1, 2), "[1, 2]")
    checkIdentity(shortArrayOf(1, 2), "[1, 2]")
    checkIdentity(intArrayOf(1, 2), "[1, 2]")
    checkIdentity(longArrayOf(1L, 2L), "[1, 2]")
    // KSwiftK deliberately renders floating-point array contents (KUU-1048).
    println(floatArrayOf(1.0f, -0.0f).contentToString())
    println(doubleArrayOf(1.0, -0.0).contentToString())
    checkIdentity(charArrayOf('a', 'b'), "[a, b]")
    checkIdentity(IntArray(0), "[]")

    val primitives = intArrayOf(1, 2)
    val mixed: Array<Any?> = arrayOf(first, primitives, null, "x")
    println(mixed.contentToString() == "[" + first.toString() + ", " + primitives.toString() + ", null, x]")
    println(mixed.contentDeepToString())
    val nullArray: Array<Any?>? = null
    println(nullArray.toString())
    println(nullArray.contentToString())
    println(nullArray.contentDeepToString())

    val before = first.toString()
    first[0] = 99
    println(first.toString() == before)
    println(first.copyOf().toString() != before)
    println(arrayOf(99, 2).toString() != before)

    val self: Array<Any?> = arrayOfNulls(1)
    self[0] = self
    checkIdentity(self, "[[...]]")
    println(self.contentToString() == "[" + self.toString() + "]")
    println(self.contentDeepToString())

    val repeated = arrayOf(second, second)
    println(repeated.contentToString() == "[" + second.toString() + ", " + second.toString() + "]")
    println(repeated.contentDeepToString())
}
