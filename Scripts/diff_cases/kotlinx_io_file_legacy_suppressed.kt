@file:Suppress("DEPRECATION_ERROR")
@file:OptIn(kotlinx.io.InternalIoApi::class)

import kotlinx.io.*
import kotlinx.io.files.*
import kotlinx.io.writeString
import kotlinx.io.readString
import kotlin.random.Random

private fun readContents(path: Path): String = SystemFileSystem.source(path).buffered().use { it.readString() }

private fun deleteIfPresent(path: Path) {
    if (SystemFileSystem.exists(path)) SystemFileSystem.delete(path, mustExist = false)
}

// This consumer checks the suppressed compatibility calls' declared types, buffering, and file errors.
fun main() {
    val suffix = Random.nextInt(1, 1000000000).toString()
    val sinkPath = Path(SystemTemporaryDirectory, "kswiftk-kuu2631-sink-$suffix")
    val sourcePath = Path(SystemTemporaryDirectory, "kswiftk-kuu2631-source-$suffix")
    val missingPath = Path(SystemTemporaryDirectory, "kswiftk-kuu2631-missing-$suffix")
    val directoryPath = Path(SystemTemporaryDirectory, "kswiftk-kuu2631-directory-$suffix")

    try {
        deleteIfPresent(sinkPath)
        deleteIfPresent(sourcePath)
        deleteIfPresent(missingPath)
        deleteIfPresent(directoryPath)

        SystemFileSystem.sink(sinkPath).buffered().use { it.writeString("previous") }
        sinkPath.sink().use { sink ->
            sink.writeString("new")
            check(sink.buffer.size == 3L)
            check(readContents(sinkPath).isEmpty())
            println("sink.buffered=true")
            println("sink.pending=empty")

            sink.emit()
            check(sink.buffer.size == 0L)
            check(readContents(sinkPath) == "new")
            println("sink.emitted=" + readContents(sinkPath))
        }

        SystemFileSystem.sink(sourcePath).buffered().use { it.writeString("source-input") }
        sourcePath.source().use { source ->
            check(source.request(1L))
            check(source.buffer.size > 1L)
            check(source.readString() == "source-input")
            println("source.buffered=true")
            println("source.read=source-input")
        }

        var missingSourceFailure = false
        try {
            missingPath.source().close()
        } catch (_: FileNotFoundException) {
            missingSourceFailure = true
        }
        check(missingSourceFailure)
        println("source.missing=FileNotFoundException")

        SystemFileSystem.createDirectories(directoryPath)
        var directorySinkFailure = false
        try {
            directoryPath.sink().close()
        } catch (_: IOException) {
            directorySinkFailure = true
        }
        check(directorySinkFailure)
        println("sink.directory=IOException")
    } finally {
        deleteIfPresent(sinkPath)
        deleteIfPresent(sourcePath)
        deleteIfPresent(missingPath)
        deleteIfPresent(directoryPath)
    }
}
