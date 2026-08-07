import kotlin.io.path.*

fun main() {
    // Test createTempFile
    val tempFile = createTempFile("test", ".tmp")
    println("temp file created: ${tempFile.exists()}")
    println("temp file name ends with .tmp: ${tempFile.name.endsWith(".tmp")}")
    println("temp file name starts with test: ${tempFile.name.startsWith("test")}")

    // Test createTempDirectory
    val tempDir = createTempDirectory("testdir")
    println("temp dir created: ${tempDir.exists()}")
    println("temp dir is directory: ${tempDir.isDirectory()}")
    println("temp dir name starts with testdir: ${tempDir.name.startsWith("testdir")}")

    // Clean up
    tempFile.deleteIfExists()
    tempDir.deleteIfExists()

    println("temp files test ok")
}
