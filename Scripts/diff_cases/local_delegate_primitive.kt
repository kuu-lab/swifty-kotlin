class IntProp {
    operator fun getValue(thisRef: Any?, property: Any?): Int = 42
}

class StringProp {
    operator fun getValue(thisRef: Any?, property: Any?): String = "hello"
}

class BooleanProp {
    operator fun getValue(thisRef: Any?, property: Any?): Boolean = true
}

fun main() {
    val i by IntProp()
    println(i)
    println(i + 1)

    val s by StringProp()
    println(s)
    println(s + " world")

    val b by BooleanProp()
    println(b)
    println(!b)
}
