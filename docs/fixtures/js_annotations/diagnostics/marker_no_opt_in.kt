@kotlin.js.ExperimentalJsExport
class ExportedBox(val value: Int = 7)
object JsHolder {
    @kotlin.js.ExperimentalJsStatic
    fun message(): String = "js-annotations"
}
fun main() {
    println(JsHolder.message())
    println(ExportedBox().value)
}
