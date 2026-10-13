@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsStatic::class)

// Markers propagate opt-in requirements; they do not export or emit static members.
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
