// KUU-3668 / JetBrains compiler/testData/codegen/box/basics/kt7972.kt:
// an erased `MutableList<E>` `is` check lets a wrong-typed element into a
// `MutableList<Int>`. Kotlin/JVM then throws ClassCastException on the
// checkcast it emits where the typed `get` result is claimed, and throws
// UnsupportedOperationException when a frozen `listOf` result is mutated.
fun <E> List<E>.addAnything(element: E) {
    if (this is MutableList<E>) {
        this.add(element)
    }
}

fun box(): String {
    val list = arrayListOf(1, 2)
    list.addAnything("string")
    try {
        val x = list[2]
        return "FAIL: $x"
    } catch (e: ClassCastException) {
        return "OK"
    }
}

fun main() {
    println(box())

    val list = arrayListOf(1, 2)
    list.addAnything("string")
    try {
        val x = list.get(2)
        println("FAIL: $x")
    } catch (e: ClassCastException) {
        println("OK")
    }
    println(list[0])
    println(list.size)

    try {
        list[2] += 1
        println("FAIL: no throw")
    } catch (e: ClassCastException) {
        println("CCE")
    }

    val frozen = listOf(1, 2)
    try {
        frozen.addAnything("string")
        println("FAIL: no throw")
    } catch (e: UnsupportedOperationException) {
        println("UOE")
    }
    println(frozen is MutableList<*>)
    println(frozen[0])
}
