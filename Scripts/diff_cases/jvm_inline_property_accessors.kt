// DIFF_JVM
inline val String.doubledLength: Int get() = length * 2

class Box {
    var raw = 0
    inline var value: Int
        get() = raw
        set(v) { raw = v }
}

class OrdinaryBox {
    var value: Int = 1
}

fun main() {
    println("abc".doubledLength)
    val box = Box()
    box.value = 7
    println(box.value)
    val ordinary = OrdinaryBox()
    ordinary.value = 9
    println(ordinary.value)
}
