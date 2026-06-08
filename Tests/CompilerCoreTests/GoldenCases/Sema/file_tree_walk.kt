import java.io.File

fun main() {
    val root = File("/tmp/tree_test")

    // walkTopDown with maxDepth and forEach
    root.walkTopDown().maxDepth(2).forEach { f ->
        println(f.name)
    }

    // walkBottomUp with onEnter and onLeave
    val walk = root.walkBottomUp()
    val filtered = walk.onEnter { dir -> dir.name != "skip" }
    val withLeave = filtered.onLeave { dir -> println("leaving: ${dir.name}") }
    withLeave.forEach { f -> println(f.path) }
}
