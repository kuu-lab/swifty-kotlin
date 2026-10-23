import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

// KUU-2015: read only the repository-owned fixture, from the harness cwd.
fun read(path: Path): ByteArray = Files.readAllBytes(path)

fun main() {
    val path: Path = Paths.get("Scripts", "diff_cases", "hello.txt")
    println(Files.exists(path))
    println(Files.exists(Paths.get("Scripts", "diff_cases", "kuu_2015_missing_fixture.txt")))
    println(String(read(path)).trim())
    println(String(read(Paths.get("Scripts/diff_cases/hello.txt"))).trim())
    println(Paths.get("Scripts//", "", "/diff_cases/", "hello.txt/").toString())
    println(Paths.get("", "Scripts", "diff_cases", "hello.txt") == path)
    println(Paths.get("/").toString())
    println(Paths.get("").toString().length)
    try {
        read(Paths.get("Scripts", "diff_cases", "kuu_2015_missing_fixture.txt"))
        println("missing: not thrown")
    } catch (failure: IOException) {
        println("missing: IOException")
    }
}
