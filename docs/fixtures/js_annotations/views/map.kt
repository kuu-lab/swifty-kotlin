@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
import kotlin.js.collections.JsMap
import kotlin.js.collections.toMap
import kotlin.js.collections.toMutableMap

class Box<T>(val value: T)
fun <K, V> observe(view: JsMap<K, V>): Map<K, V> = view.toMap()

fun main() {
    val minimum = mutableMapOf("a" to 1, "b" to 2).asJsMapView()
    println("minimum:${minimum.toMap().size}")
    val backing = linkedMapOf<String?, Box<Int>?>("a" to Box(1), "b" to null)
    val view: JsMap<String?, Box<Int>?> = backing.asJsMapView()
    val snapshot = observe(view)
    val copy = view.toMutableMap()
    backing["a"] = Box(7)
    backing[null] = Box(4)
    println("replace:${observe(view)["a"]?.value}:${observe(view)[null]?.value}:${observe(view).containsKey("b")}")
    backing.remove("b")
    backing["c"] = Box(3)
    println("ordered:${observe(view).keys.joinToString(",")}:${observe(view)["c"]?.value}")
    copy["a"] = Box(99)
    copy.remove("b")
    copy.clear()
    println("copies:${observe(view)["a"]?.value}:${snapshot["a"]?.value}:${snapshot.size}:${copy.size}")
    backing.clear()
    println("clear:${observe(view).size}:${snapshot.size}")
    backing["again"] = null
    println("reuse:${observe(view).size}:${observe(view).containsKey("again")}:${observe(view)["again"]}")
    val empty = mutableMapOf<String, Int>()
    val emptyView = empty.asJsMapView()
    println("empty:${emptyView.toMap().size}")
    empty["later"] = 8
    println("grown:${emptyView.toMap()["later"]}:${emptyView.toMap().size}")
}
