@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
import kotlin.js.collections.JsSet
import kotlin.js.collections.toSet
import kotlin.js.collections.toMutableSet

fun <T> observe(view: JsSet<T>): Set<T> = view.toSet()

fun main() {
    println("minimum:${mutableSetOf("x", "y", "z").asJsSetView().toSet().size}")
    val backing = linkedSetOf<String?>("x", null, "y", "x")
    val view: JsSet<String?> = backing.asJsSetView()
    val snapshot = observe(view)
    val copy = view.toMutableSet()
    println("initial:${observe(view).joinToString(",")}:${observe(view).contains(null)}")
    println("changes:${backing.add("z")}:${backing.add("x")}:${backing.remove("y")}:${backing.remove("missing")}")
    println("ordered:${observe(view).joinToString(",")}")
    copy.add("copy")
    copy.remove("x")
    copy.clear()
    println("copies:${observe(view).joinToString(",")}:${snapshot.joinToString(",")}:${copy.size}")
    backing.clear()
    println("clear:${observe(view).size}:${snapshot.size}")
    backing.add("again")
    backing.add(null)
    println("reuse:${observe(view).joinToString(",")}")
    val empty = mutableSetOf<Int?>()
    val emptyView = empty.asJsSetView()
    println("empty:${emptyView.toSet().size}")
    empty.add(8)
    empty.add(null)
    println("grown:${emptyView.toSet().joinToString(",")}")
}
