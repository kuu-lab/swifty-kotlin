typealias ArrayS = Array<String>

fun testArrayConstructor() {
    Array<String>(5) { i ->
        if (i == 3) return
        i.toString()
    }
    throw AssertionError()
}

fun testArrayConstructorAlias() {
    ArrayS(5) { i ->
        if (i == 3) return
        i.toString()
    }
    throw AssertionError()
}

fun testIntArrayConstructor() {
    IntArray(5) { i ->
        if (i == 3) return
        i
    }
    throw AssertionError()
}

fun main() {
    testArrayConstructor()
    testArrayConstructorAlias()
    testIntArrayConstructor()
    println("OK")
}
