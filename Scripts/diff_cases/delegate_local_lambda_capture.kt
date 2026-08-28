class IntProp {
    var backing: Int = 1

    operator fun getValue(thisRef: Any?, property: Any?): Int = backing

    operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
        backing = value
    }
}

fun main() {
    var value by IntProp()
    val update = {
        println(value)
        value = 7
        println(value)
    }
    update()
}
