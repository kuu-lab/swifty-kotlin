// JetBrains Kotlin 2.3.10 compiler/testData/codegen/box/typealias/typeAliasConstructorForArray.kt
typealias BoolArray = Array<Boolean>
typealias IArray = IntArray
typealias MyArray<T> = Array<T>

fun box(): String {
    val ba = BoolArray(1) { true }
    if (!ba[0]) return "Fail #1"

    val ia = IArray(1) { 42 }
    if (ia[0] != 42) return "Fail #2"

    val ma = MyArray<Int>(1) { 42 }
    if (ma[0] != 42) return "Fail #2"

    return "OK"
}

fun main() {
    println(box())
}
