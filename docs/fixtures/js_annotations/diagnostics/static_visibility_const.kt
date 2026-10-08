@file:OptIn(kotlin.js.ExperimentalJsStatic::class)
class Holder {
    companion object {
        @kotlin.js.JsStatic
        private fun hidden() {}
        @kotlin.js.JsStatic
        const val answer: Int = 7
        @kotlin.js.JsStatic
        var limited: Int = 7
            private set
    }
}
fun main() {}
