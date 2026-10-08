@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
fun main() {
    println(mutableMapOf("a" to 1).asJsMapView().size)
    println(mutableSetOf("x").asJsSetView().size)
    val list = listOf(1, 2, 3, 4)
    println(list.asJsReadonlyArrayView().size)
    println(list.asJsReadonlyArrayView().length)
}
