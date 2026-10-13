import kotlinx.io.files.*
import platform.posix.F_OK
import platform.posix.access

// Test adapter domain only: canonical paths and F_OK; no general POSIX claim.
fun main() {
    val path = Path(SystemTemporaryDirectory, "kswiftk-b06-adapter-" + kotlin.random.Random.nextInt(1, 1000000000))
    SystemFileSystem.sink(path).close()
    try {
        println("access-existing:${access(path.toString(), F_OK)}")
        println("access-missing:${access(path.toString() + "-absent", F_OK)}")
        try { access(path.toString(), 4); println("access-mode:NO_EXCEPTION") }
        catch (failure: IllegalArgumentException) { println("access-mode:IllegalArgumentException") }
        try { access(path.toString() + "/", F_OK); println("access-noncanonical:NO_EXCEPTION") }
        catch (failure: IllegalArgumentException) { println("access-noncanonical:IllegalArgumentException") }
    } finally { SystemFileSystem.delete(path, mustExist = false) }
}
