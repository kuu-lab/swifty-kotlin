package f02producer

import kotlinx.io.IOException
import kotlinx.io.files.FileSystem
import kotlinx.io.files.FileSystemFlagProbe
import kotlinx.io.files.Path

public fun runDefaultFlagProbe(): String {
    val probe = FileSystemFlagProbe()
    val fs: FileSystem = probe
    val path = Path("kuu2630-probe")

    val defaultSinkFailed = try {
        fs.sink(path)
        false
    } catch (_: IOException) {
        true
    }
    check(defaultSinkFailed && probe.sinkAppend == false)
    val explicitSinkFailed = try {
        fs.sink(path, append = true)
        false
    } catch (_: IOException) {
        true
    }
    check(explicitSinkFailed && probe.sinkAppend == true)

    fs.delete(path)
    check(probe.deleteMustExist == true)
    fs.delete(path, mustExist = false)
    check(probe.deleteMustExist == false)

    fs.createDirectories(path)
    check(probe.createDirectoriesMustCreate == false)
    fs.createDirectories(path, mustCreate = true)
    check(probe.createDirectoriesMustCreate == true)

    return "sink-default-append=false:explicit-true=true\n" +
        "delete-default-mustExist=true:explicit-false=false\n" +
        "createDirectories-default-mustCreate=false:explicit-true=true"
}
