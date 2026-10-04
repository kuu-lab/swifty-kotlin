import kotlinx.io.IOException
import kotlinx.io.files.*
import kotlin.random.Random

fun main() {
    val fs: FileSystem = SystemFileSystem
    val root = Path(SystemTemporaryDirectory, "kswiftk-fs-errors-" + Random.nextInt(1, 1000000000))
    val child = Path(root, "child")
    val missing = Path(root, "missing")
    fs.createDirectories(child, true)
    try {
        try {
            fs.delete(root)
        } catch (e: IOException) {
            println("nonempty directory")
        }
        println(fs.exists(child))
        try {
            fs.createDirectories(root, true)
        } catch (e: IOException) {
            println("already exists")
        }
        try {
            fs.delete(missing)
        } catch (e: FileNotFoundException) {
            println("missing delete")
        }
        try {
            fs.atomicMove(missing, child)
        } catch (e: FileNotFoundException) {
            println("missing source")
        }
        try {
            fs.list(missing)
        } catch (e: FileNotFoundException) {
            println("missing list")
        }
        try {
            fs.resolve(missing)
        } catch (e: FileNotFoundException) {
            println("missing resolve")
        }
        try {
            fs.delete(missing)
        } catch (e: IOException) {
            println("missing caught as IO")
        }
    } finally {
        fs.delete(child)
        fs.delete(root)
    }
}
