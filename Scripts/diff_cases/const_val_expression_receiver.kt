// KUU-2862: inlining an object const val still evaluates an expression receiver.
val sb = StringBuilder()
object C {
    init { sb.appendLine("C init") }
    const val x = 42
}
fun getC(): C {
    sb.appendLine(123)
    return C
}
fun main() {
    sb.appendLine(C.x)
    sb.appendLine(getC().x)
    print(sb.toString())
}
