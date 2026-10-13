@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)

// JS-only observations. These dynamic operations are outside the native compatibility surface.
fun main() {
    val map = mutableMapOf("a" to 1, "b" to 2)
    val mapView = map.asJsMapView().asDynamic()
    val set = mutableSetOf("x", "y", "z")
    val setView = set.asJsSetView().asDynamic()
    val list = mutableListOf(1, 2, 3, 4)
    val arrayView = list.asJsReadonlyArrayView().asDynamic()
    println("${mapView.size}:${setView.size}:${arrayView.length}")
    println("array-size:${kotlin.js.jsTypeOf(arrayView.size)}")

    map["c"] = 3
    println("map-backing:${mapView.size}:${mapView.get("c")}")
    println("map-chain:${mapView.set("a", 7) === mapView}:${map["a"]}")
    val mapDelete = mapView.`delete`("b")
    println("map-delete:${kotlin.js.jsTypeOf(mapDelete)}:${mapDelete === Unit}:${map.size}")

    set.add("w")
    println("set-backing:${setView.size}:${setView.has("w")}")
    println("set-chain:${setView.add("v") === setView}:${set.contains("v")}")
    println("set-delete:${setView.`delete`("y")}:${set.contains("y")}")

    list[0] = 7
    list.add(5)
    println("array-backing:${arrayView.length}:${arrayView[0]}")
    try {
        arrayView[0] = 99
        println("readonly:write-succeeded")
    } catch (e: UnsupportedOperationException) {
        println("readonly:UnsupportedOperationException:${list[0]}")
    }
}
