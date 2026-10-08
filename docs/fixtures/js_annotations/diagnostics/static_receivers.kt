@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsStatic::class)
@kotlin.js.JsStatic
fun topLevel() {}
object Holder {
    @kotlin.js.JsStatic
    fun objectMember() {}
}
class Ordinary {
    @kotlin.js.JsStatic
    fun member() {}
    companion object {
        @kotlin.js.JsStatic
        fun companionMember() {}
    }
}
fun main() {}
