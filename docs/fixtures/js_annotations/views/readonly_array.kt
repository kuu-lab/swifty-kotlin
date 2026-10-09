@file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
import kotlin.js.collections.JsReadonlyArray
import kotlin.js.collections.toList
import kotlin.js.collections.toMutableList

fun <T> observe(view: JsReadonlyArray<T>): List<T> = view.toList()

fun main() {
    val backing = mutableListOf<Int?>(1, null, 3, 4)
    val view: JsReadonlyArray<Number?> = backing.asJsReadonlyArrayView()
    val snapshot = observe(view)
    val copy = view.toMutableList()
    println("minimum:${observe(view).size}:${observe(view).joinToString(",")}")
    backing[0] = 7
    backing.add(5)
    backing.removeAt(2)
    println("changed:${observe(view).joinToString(",")}")
    copy[0] = 99
    copy.add(8)
    copy.clear()
    println("copies:${observe(view).joinToString(",")}:${snapshot.joinToString(",")}:${copy.size}")
    backing.clear()
    println("clear:${observe(view).size}:${snapshot.size}")
    backing.add(null)
    backing.add(6)
    println("reuse:${observe(view).joinToString(",")}")
    val empty = mutableListOf<String?>()
    val emptyView = empty.asJsReadonlyArrayView()
    println("empty:${emptyView.toList().size}")
    empty.add("later")
    println("grown:${emptyView.toList().joinToString(",")}")
    println("immutable:${listOf(4, 3, 2, 1).asJsReadonlyArrayView().toList().joinToString(",")}")
}
