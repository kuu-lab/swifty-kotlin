class IntProp {
    var backing: Int = 42

    operator fun getValue(thisRef: Any?, property: Any?): Int = backing
}

fun main() {
    val value by IntProp()

    fun readValue(): Int = value

    println(readValue())
}
