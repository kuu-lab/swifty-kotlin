import java.nio.file.Files

fun main() {
    val legacyChar = 65.toChar()
    println(legacyChar)

    val legacySlice = "kotlin".subSequence(1, 4)
    println(legacySlice)

    val tempDir = Files.createTempDirectory("kswiftk-").toFile()
    println(tempDir.exists())
    println(tempDir.isDirectory)

    val tempFile = Files.createTempFile(tempDir.toPath(), "kswiftk-", ".tmp").toFile()
    println(tempFile.exists())
    println(tempFile.isFile)

    tempFile.delete()
    tempDir.delete()
}
