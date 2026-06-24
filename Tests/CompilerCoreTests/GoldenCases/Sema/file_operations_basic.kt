import java.io.File

fun main() {
    val testDir = File("/tmp/test_mkdirs")
    val mkdirsResult = testDir.mkdirs()
    println(mkdirsResult)

    val existsResult = testDir.exists()
    println(existsResult)

    val isDirResult = testDir.isDirectory()
    println(isDirResult)

    val files = testDir.listFiles()
    println(files)

    val walkResult = testDir.walk()
    println(walkResult)

    val deleteResult = testDir.delete()
    println(deleteResult)
}
