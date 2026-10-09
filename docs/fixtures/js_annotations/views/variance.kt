@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
import kotlin.js.collections.JsMap
import kotlin.js.collections.JsSet
import kotlin.js.collections.JsReadonlyArray

fun widenMapKey(view: JsMap<String, Int>): JsMap<Any, Int> = view
fun widenMapValue(view: JsMap<String, Int>): JsMap<String, Number> = view
fun widenSet(view: JsSet<String>): JsSet<Any> = view
fun narrowArray(view: JsReadonlyArray<Number?>): JsReadonlyArray<Int?> = view
