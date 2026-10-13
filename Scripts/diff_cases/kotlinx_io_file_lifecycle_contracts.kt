import kotlinx.io.*
import kotlinx.io.files.*
import kotlin.random.Random

// All lifecycle operations use the public FileSystem interface and real files.
fun main() {
    val fs: FileSystem = SystemFileSystem
    val root = Path(SystemTemporaryDirectory, "kswiftk-b06-" + Random.nextInt(1, 1000000000))
    val file = Path(root, "data")
    val target = Path(root, "moved")
    val nested = Path(root, "nested")
    fs.createDirectories(nested, mustCreate = true)
    try {
        fs.createDirectories(nested)
        println("directories:${fs.exists(nested)}")
        fs.sink(file).buffered().use { it.writeString("first") }
        fs.sink(file).buffered().use { it.writeString("second") }
        fs.sink(file, append = true).buffered().use { it.writeString("+"); it.flush() }
        fs.source(file).buffered().use { println("append:${it.readString()}") }
        println("size:${fs.metadataOrNull(file)!!.size}")
        println("directory-size:${fs.metadataOrNull(nested)!!.size}")
        val sink = fs.sink(target)
        sink.close()
        sink.close()
        val source = fs.source(target)
        source.close()
        source.close()
        println("double-close:${fs.exists(target)}")
        fs.atomicMove(file, target)
        println("atomic:${!fs.exists(file)}:${fs.exists(target)}")
        fs.source(target).buffered().use { println("moved:${it.readString()}") }
        println("list:${fs.list(root).toSet() == setOf(target, nested)}")
        println("resolved:${fs.resolve(root).isAbsolute}")
        println("metadata-missing:${fs.metadataOrNull(file) == null}")
        try { fs.delete(file); println("missing-delete:NO_EXCEPTION") }
        catch (failure: FileNotFoundException) { println("missing-delete:FileNotFoundException") }
        fs.delete(file, mustExist = false)
        try { fs.createDirectories(target); println("file-directory:NO_EXCEPTION") }
        catch (failure: IOException) { println("file-directory:IOException") }
        try { fs.delete(root); println("nonempty:NO_EXCEPTION") }
        catch (failure: IOException) { println("nonempty:IOException") }
        try { fs.source(file); println("missing-source:NO_EXCEPTION") }
        catch (failure: FileNotFoundException) { println("missing-source:FileNotFoundException") }
    } finally {
        fs.delete(target, mustExist = false)
        fs.delete(file, mustExist = false)
        fs.delete(nested, mustExist = false)
        fs.delete(root, mustExist = false)
    }
}
