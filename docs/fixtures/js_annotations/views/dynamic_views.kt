@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)

// Kotlin/JS reference only: these operations have no typed native counterpart.
fun main() {
    val map = linkedMapOf<String?, Int?>("a" to 1, "b" to null)
    val mapView = map.asJsMapView().asDynamic()
    println("map-initial:${mapView.size}:${mapView.get("b")}")
    println("map-chain:${mapView.set("a", 7) === mapView}:${map["a"]}")
    mapView.set(null, 4)
    map.remove("b")
    println("map-shared:${map[null]}:${mapView.has("b")}:${mapView.size}")
    val deleted = mapView.`delete`("a")
    println("map-delete:${deleted === Unit}:${map.containsKey("a")}:${map.size}")
    mapView.clear()
    println("map-clear:${map.size}:${mapView.size}")
    map["again"] = 8
    println("map-reuse:${mapView.get("again")}:${mapView.size}")

    val set = linkedSetOf<String?>("x", null)
    val setView = set.asJsSetView().asDynamic()
    println("set-chain:${setView.add("y") === setView}:${set.contains("y")}")
    setView.add("y")
    set.remove("x")
    println("set-shared:${setView.size}:${setView.has(null)}:${setView.has("x")}")
    println("set-delete:${setView.`delete`("y")}:${set.contains("y")}:${setView.`delete`("missing")}")
    setView.clear()
    println("set-clear:${set.size}:${setView.size}")
    set.add("again")
    println("set-reuse:${setView.has("again")}:${setView.size}")

    val backing = mutableListOf<Int?>(1, null, 3, 4)
    val array = backing.asJsReadonlyArrayView().asDynamic()
    backing[0] = 7
    backing.add(5)
    backing.removeAt(2)
    println("array-shared:${array.length}:${array[0]}:${array[1]}:${array[3]}")
    try { array[0] = 99; println("write-succeeded") }
    catch (e: UnsupportedOperationException) { println("readonly:${backing[0]}") }
    backing.clear()
    println("array-clear:${array.length}")
    backing.add(6)
    println("array-reuse:${array.length}:${array[0]}")
}
