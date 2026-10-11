import kotlinx.io.IOException
import kotlinx.io.files.*

// Expected from pinned common/native source; preparation only, not executed.
fun main() {
    val defaults = FileMetadata()
    println("metadata-defaults:${defaults.isRegularFile}:${defaults.isDirectory}:${defaults.size}")
    val directory = FileMetadata(isDirectory = true)
    println("metadata-partial:${directory.isRegularFile}:${directory.isDirectory}:${directory.size}")
    val file = FileMetadata(size = 7L, isRegularFile = true)
    println("metadata-named:${file.isRegularFile}:${file.isDirectory}:${file.size}")
    val absent = FileNotFoundException(null)
    println("nullable-message:${absent.message == null}")
    println("io-supertype:${absent is IOException}")
    println("factory-named:${Path(path = "a///")}")
    println("string-vararg-empty:${Path(base = "a")}")
    println("path-vararg-empty:${Path(base = Path("a"))}")
    val parts = arrayOf("b", "c")
    println("string-vararg-spread:${Path("a", *parts)}")
    println("path-vararg-spread:${Path(Path("a"), *parts)}")
    val equal = Path("a", "b")
    println("hash-contract:${equal.hashCode() == equal.toString().hashCode()}")
    println("equal-hash:${equal.hashCode() == Path("a/b").hashCode()}")
    println("singleton-identity:${SystemFileSystem === SystemFileSystem}")
    println("separator:$SystemPathSeparator")
}
