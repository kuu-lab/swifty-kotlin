// Reproduction from JetBrains/kotlin compiler/testData/codegen/box/callableReference/property/kt15447.kt.
// Pinned source: https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/callableReference/property/kt15447.kt
// SHA-256: 22d18669b2040a0b2c5d670db66116944cf77fa477086b82c8a182e18af5c2f9
fun box(): String {
    var methodVar = "OK"

    fun localMethod(): String
    {
        return lazy { methodVar }::value.get()
    }

    return localMethod()
}

fun minimized(): String = lazy { "OK" }::value.get()
fun directRead(): String = lazy { "OK" }.value

class ConcreteBox(val value: String)
fun nonGenericBoundReference(): String = ConcreteBox("OK")::value.get()

fun main() {
    println(box())
    println(minimized())
    println(directRead())
    println(nonGenericBoundReference())
}
