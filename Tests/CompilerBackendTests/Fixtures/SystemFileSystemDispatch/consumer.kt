import kotlinx.io.*
import kotlinx.io.files.*

fun main() {
    println("before exists")
    println(SystemFileSystem.exists(Path("Hello.kt")))
    println("after exists")

    val fs: FileSystem = SystemFileSystem
    val missing = Path("missing.kt")
    println("local exists:${fs.exists(Path("Hello.kt"))}")
    println("missing exists:${SystemFileSystem.exists(missing)}:${fs.exists(missing)}")

    val direct = SystemFileSystem.source(Path("Hello.kt"))
    val directBuffer = Buffer()
    println("direct read:${direct.readAtMostTo(directBuffer, 100)}")
    println(directBuffer.readString())
    println("direct eof:${direct.readAtMostTo(directBuffer, 100)}")
    direct.close()

    val local = fs.source(Path("Hello.kt"))
    val localBuffer = Buffer()
    println("local read:${local.readAtMostTo(localBuffer, 100)}")
    println(localBuffer.readString())
    local.close()

    try {
        SystemFileSystem.source(missing)
        println("unexpected direct source")
    } catch (e: FileNotFoundException) {
        println("direct missing source")
    }
    try {
        fs.source(missing)
        println("unexpected local source")
    } catch (e: FileNotFoundException) {
        println("local missing source")
    }
}
