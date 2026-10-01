import kotlinx.io.files.Path
import kotlinx.io.files.SystemPathSeparator

fun main() {
    val path = Path("/tmp/logs/today/")
    println(path.toString())
    println(path.name)
    println(path.parent)
    println(path.isAbsolute)
    println(path == Path("/tmp/logs/today"))
    println(Path("relative", "images", "file.txt"))
    println(Path(Path("/tmp"), "note.txt"))
    println(Path("file.txt").parent)
    println(Path("/").name)
    println(SystemPathSeparator)
}
