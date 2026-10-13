@file:OptIn(kotlin.js.ExperimentalJsExport::class)
class InternalBox(val value: Int)
@kotlin.js.JsExport
fun value(): InternalBox = InternalBox(7)
fun main() {}
