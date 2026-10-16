// KUU-2444: A receiver-function invocation result must use its return type in equality checks.
// Adapted from JetBrains/kotlin's pinned Kotlin 2.3.10 box test:
// https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/extensionFunctions/nested2.kt
fun box(): String {
    val y = 12
    val op = { x: Int -> (x + y).toString() }

    val op2: Int.(Int) -> String = { op(this + it) }

    return if ("27" == 5.op2(10)) "OK" else "fail"
}

fun main() {
    println(box())
}
