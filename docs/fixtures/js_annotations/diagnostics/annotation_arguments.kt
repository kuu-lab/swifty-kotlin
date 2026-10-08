@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsStatic::class)
@kotlin.js.JsExport("bad")
class Box {
    companion object {
        @kotlin.js.JsStatic("bad")
        fun message(): String = "js-annotations"
    }
}
@kotlin.js.ExperimentalJsExport("bad")
class Marked
@kotlin.js.ExperimentalJsStatic("bad")
fun marked() {}
fun main() {}
