import java.io.File
import kotlin.io.FileTreeWalk

fun testWalkTopDown(dir: File): FileTreeWalk = dir.walkTopDown()
fun testWalkBottomUp(dir: File): FileTreeWalk = dir.walkBottomUp()
fun testMaxDepth(dir: File): FileTreeWalk = dir.walkTopDown().maxDepth(2)
fun testToList(dir: File): List<File> = dir.walkTopDown().toList()
fun testOnEnter(dir: File): FileTreeWalk = dir.walkTopDown().onEnter { it.name != "skip" }
fun testOnLeave(dir: File): FileTreeWalk = dir.walkTopDown().onLeave { println(it.name) }
fun testForEach(dir: File) {
    dir.walkTopDown().maxDepth(3).onEnter { d -> d.name != "skip" }.forEach { f ->
        println(f.name)
    }
}
