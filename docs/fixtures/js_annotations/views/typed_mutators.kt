@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
fun main() {
    mutableMapOf("a" to 1).asJsMapView().set("b", 2)
    mutableSetOf("x").asJsSetView().add("y")
    listOf(1).asJsReadonlyArrayView().add(2)
    listOf(1).asJsReadonlyArrayView().set(0, 2)
}
