@file:kotlin.js.JsFileName("NoOptIn")
import kotlin.reflect.createInstance
@kotlin.js.JsExport
class Box(val value: Int = 7) {
    companion object {
        @kotlin.js.JsStatic
        fun message(): String = "js-annotations"
    }
}
fun main() {
    mutableMapOf("a" to 1).asJsMapView()
    mutableSetOf("x").asJsSetView()
    listOf(1).asJsReadonlyArrayView()
    Box::class.createInstance()
}
