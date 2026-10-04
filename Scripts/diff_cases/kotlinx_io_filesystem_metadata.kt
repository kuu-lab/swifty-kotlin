import kotlinx.io.files.*
import kotlin.random.Random

fun main() {
    val fs: FileSystem = SystemFileSystem
    val root = Path(SystemTemporaryDirectory, "kswiftk-fs-metadata-" + Random.nextInt(1, 1000000000))
    val nested = Path(root, "a", "b")
    val moved = Path(root, "moved")
    try {
        println(fs.exists(root))
        println(fs.metadataOrNull(root) == null)
        fs.createDirectories(nested)
        fs.createDirectories(nested)
        println(SystemFileSystem.exists(nested))
        val metadata = SystemFileSystem.metadataOrNull(nested)!!
        println(metadata.isRegularFile)
        println(metadata.isDirectory)
        println(metadata.size)
        println(fs.list(root).map { it.name }.sorted())
        println(fs.list(nested).isEmpty())
        println(fs.resolve(Path(nested, "..", ".", "b")) == fs.resolve(nested))
        println(fs.resolve(nested).isAbsolute)
        fs.atomicMove(nested, moved)
        println(fs.exists(nested))
        println(fs.exists(moved))
        fs.delete(moved)
        fs.delete(moved, false)
        println(fs.exists(moved))
        val defaults = FileMetadata()
        println(defaults.isRegularFile)
        println(defaults.isDirectory)
        println(defaults.size)
    } finally {
        fs.delete(moved, false)
        fs.delete(nested, false)
        fs.delete(Path(root, "a"), false)
        fs.delete(root, false)
    }
}
