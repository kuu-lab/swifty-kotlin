import java.io.File
import kotlin.io.FileTreeWalk

fun testWalkTopDown(dir: File): FileTreeWalk = dir.walkTopDown()
fun testWalkBottomUp(dir: File): FileTreeWalk = dir.walkBottomUp()
fun testMaxDepth(dir: File): FileTreeWalk = dir.walkTopDown().maxDepth(2)
fun testToList(dir: File): List<File> = dir.walkTopDown().toList()
