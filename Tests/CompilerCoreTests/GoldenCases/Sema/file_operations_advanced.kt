import java.io.File

fun main() {
    val baseDir = File("/tmp/advanced_test")
    val subDir = File("/tmp/advanced_test/subdir")
    val nestedDir = File("/tmp/advanced_test/subdir/nested")

    val mkdirsResult = nestedDir.mkdirs()
    println(mkdirsResult)

    val walkedFiles = baseDir.walk()
    println(walkedFiles.toList().size)

    val baseFiles = baseDir.listFiles()
    println(baseFiles?.toList()?.size)

    val subFiles = subDir.listFiles()
    println(subFiles?.toList()?.size)

    val deleteBaseResult = baseDir.delete()
    println(deleteBaseResult)

    File("/tmp/advanced_test/file1.txt").delete()
    File("/tmp/advanced_test/subdir/file2.txt").delete()
    subDir.delete()
    val finalDeleteResult = baseDir.delete()
    println(finalDeleteResult)
}
