package f02producer

import java.util.UUID
import kotlinx.io.IOException
import kotlinx.io.buffered
import kotlinx.io.files.FileSystem
import kotlinx.io.files.FileNotFoundException
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString

public fun runDefaultFlagProbe(): String {
    val fs: FileSystem = SystemFileSystem
    val root = Path(System.getProperty("java.io.tmpdir"), "kuu2630-${UUID.randomUUID()}")
    val sinkPath = Path(root, "sink")
    val missingPath = Path(root, "missing")
    val directoryPath = Path(root, "directory")

    fs.createDirectories(root)
    fs.sink(sinkPath).buffered().use { it.writeString("first") }
    fs.sink(sinkPath).buffered().use { it.writeString("second") }
    check(fs.source(sinkPath).buffered().use { it.readString() } == "second")
    fs.sink(sinkPath, append = true).buffered().use { it.writeString("-explicit") }
    check(fs.source(sinkPath).buffered().use { it.readString() } == "second-explicit")

    val defaultDeleteFailed = try {
        fs.delete(missingPath)
        false
    } catch (_: FileNotFoundException) {
        true
    }
    check(defaultDeleteFailed)
    fs.delete(missingPath, mustExist = false)

    fs.createDirectories(directoryPath)
    val explicitCreateFailed = try {
        fs.createDirectories(directoryPath, mustCreate = true)
        false
    } catch (_: IOException) {
        true
    }
    check(explicitCreateFailed)

    fs.delete(sinkPath)
    fs.delete(directoryPath)
    fs.delete(root)

    return "sink-default-append=false:explicit-true=true\n" +
        "delete-default-mustExist=true:explicit-false=false\n" +
        "createDirectories-default-mustCreate=false:explicit-true=true"
}
