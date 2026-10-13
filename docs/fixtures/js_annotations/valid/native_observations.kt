@file:OptIn(
    kotlin.js.ExperimentalJsFileName::class,
    kotlin.js.ExperimentalJsExport::class,
    kotlin.js.ExperimentalJsStatic::class,
    kotlin.js.ExperimentalJsCollectionsApi::class,
    kotlin.js.ExperimentalJsReflectionCreateInstance::class
)
@file:kotlin.js.JsFileName("JsAnnotationsCase")

import kotlin.js.collections.toList
import kotlin.js.collections.toMap
import kotlin.js.collections.toSet
import kotlin.reflect.createInstance

@kotlin.js.JsExport
class ExportedBox(val value: Int = 7)

@kotlin.js.JsExport
class JsHolder {
    companion object {
        @kotlin.js.JsStatic
        fun message(): String = "js-annotations"
    }
}

fun collectionSummary(): String {
    val map = mutableMapOf("a" to 1, "b" to 2)
    val set = mutableSetOf("x", "y", "z")
    val list = listOf(1, 2, 3, 4)
    return "${map.asJsMapView().toMap().size}:${set.asJsSetView().toSet().size}:${list.asJsReadonlyArrayView().toList().size}"
}

fun reflectionApiToken(): String {
    val factory = (ExportedBox::class)::createInstance
    val instance = ExportedBox::class.createInstance()
    check(factory().value == 7)
    return "${ExportedBox::class.simpleName}:${factory.name}:${instance.value}"
}

fun main() {
    println(JsHolder.message())
    println(collectionSummary())
    println(reflectionApiToken())
}
