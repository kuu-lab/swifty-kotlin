@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)

import kotlin.js.collections.JsMap
import kotlin.js.collections.JsReadonlyArray
import kotlin.js.collections.JsSet
import kotlin.js.collections.toList
import kotlin.js.collections.toMap
import kotlin.js.collections.toMutableList
import kotlin.js.collections.toMutableMap
import kotlin.js.collections.toMutableSet
import kotlin.js.collections.toSet

fun main() {
    val map = linkedMapOf<String, Int?>("a" to 1, "b" to null)
    val mapView: JsMap<String, Int?> = map.asJsMapView()
    val mapSnapshot = mapView.toMap()
    val mapCopy = mapView.toMutableMap()
    map["c"] = 3
    mapCopy.clear()
    println("map:${mapView.toMap().size}:${mapView.toMap()["b"]}:${mapCopy.size}:${mapSnapshot.size}")

    val set = linkedSetOf<String?>("x", null)
    val setView: JsSet<String?> = set.asJsSetView()
    val setSnapshot = setView.toSet()
    val setCopy = setView.toMutableSet()
    set.add("y")
    set.add("y")
    setCopy.clear()
    println("set:${setView.toSet().size}:${setView.toSet().contains(null)}:${setCopy.size}:${setSnapshot.size}")

    val list = mutableListOf(1, 2, 3, 4)
    val arrayView: JsReadonlyArray<Number> = list.asJsReadonlyArrayView()
    val listSnapshot = arrayView.toList()
    val listCopy = arrayView.toMutableList()
    list[0] = 7
    list.add(5)
    listCopy.clear()
    println("array:${arrayView.toList().joinToString(",")}:${listCopy.size}:${listSnapshot.joinToString(",")}")

    println("empty:${mutableMapOf<String, Int>().asJsMapView().toMap().size}:${mutableSetOf<String>().asJsSetView().toSet().size}:${listOf<Int>().asJsReadonlyArrayView().toList().size}")
}
