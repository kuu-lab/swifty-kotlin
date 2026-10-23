import java.io.File
import java.nio.file.Path as NioPath
import kotlin.io.path.Path

fun main() {
    println(File(".").exists())
    println(File("/").exists())
    println(File("/__kswiftk_kuu3051_missing__").exists())
    println(File(".").isAbsolute)
    println(File("/").isAbsolute)
    val workingDirectory = java.lang.System.getProperty("user.dir")!!
    println(File("").absolutePath == workingDirectory)
    println(File(".").absolutePath == "$workingDirectory/.")
    println(File("segments//leaf/").absolutePath == "$workingDirectory/segments/leaf")
    println(File("/tmp//x/").absolutePath == "/tmp/x")
    val path: NioPath = Path("segments//leaf/")
    println(path.toString())
    println(Path("/").toFile().path)
}
