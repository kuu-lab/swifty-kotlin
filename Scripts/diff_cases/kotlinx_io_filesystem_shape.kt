import kotlinx.io.RawSink
import kotlinx.io.RawSource
import kotlinx.io.files.FileMetadata
import kotlinx.io.files.FileSystem
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem

// IO-GATE KUU-2642: pin the public FileSystem interface shape independently
// from tests that only call SystemFileSystem operations.
@Suppress("UNUSED_VARIABLE")
private fun useDeclaredMembers(fs: FileSystem, path: Path, destination: Path): FileSystem {
    val exists: Boolean = fs.exists(path)
    fs.delete(path, mustExist = false)
    fs.createDirectories(destination, mustCreate = false)
    fs.atomicMove(path, destination)
    val source: RawSource = fs.source(path)
    val sink: RawSink = fs.sink(path, append = false)
    val metadata: FileMetadata? = fs.metadataOrNull(path)
    val resolved: Path = fs.resolve(path)
    val children: Collection<Path> = fs.list(path)
    return fs
}

private fun roundTrip(fs: FileSystem): FileSystem = fs

fun main() {
    val fileSystem = roundTrip(SystemFileSystem)
    if (!fileSystem.exists(Path("."))) error("current directory should exist")
    println("FileSystem public interface shape: ok")
}
