class IntProp {
    var backing: Int = 0
    operator fun getValue(thisRef: Any?, property: Any?): Int = backing
    operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
        backing = value
    }
}

fun main() {
    var x by IntProp()
    println(x)
    x = 100
    println(x)
    println(x + 1)
}
