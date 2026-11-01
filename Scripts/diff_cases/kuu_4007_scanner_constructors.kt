// DIFF_STDIN_EOF
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.charset.Charset
import java.nio.file.Paths
import java.util.Scanner
import kotlinx.io.*
import kotlinx.io.files.*

// KUU-4007: java.util.Scanner constructor overloads beyond Scanner(String):
// File / InputStream / Path sources, charsetName and Charset overloads, and
// the no-arg System.in constructor.
fun main() {
    val root = Path(SystemTemporaryDirectory, "kswiftk-kuu4007-scanner.txt")
    SystemFileSystem.sink(root).buffered().use { sink ->
        sink.writeString("alpha beta\nLINE TWO\nlast")
    }
    val filePath = root.toString()

    // Scanner(File)
    val fromFile = Scanner(File(filePath))
    println(fromFile.next())
    println(fromFile.next())
    println(fromFile.nextLine())
    println(fromFile.nextLine())
    println(fromFile.hasNext())
    fromFile.close()

    // Scanner(File, charsetName) / Scanner(Path[, charsetName])
    println(Scanner(File(filePath), "UTF-8").nextLine())
    println(Scanner(Paths.get(filePath)).next())
    println(Scanner(Paths.get(filePath), "UTF-8").next())

    // Scanner(InputStream[, charsetName])
    println(Scanner("x y".byteInputStream()).next())
    println(Scanner("s t".byteInputStream(), "UTF-8").next())

    // Scanner(source, Charset) overloads
    val utf8: Charset = Charset.forName("UTF-8")
    println(Scanner(File(filePath), utf8).next())
    println(Scanner(Paths.get(filePath), utf8).next())
    println(Scanner("m n".byteInputStream(), utf8).next())

    // Scanner(System.in) reads stdin; DIFF_STDIN_EOF puts it at EOF immediately.
    println(Scanner(System.`in`).hasNext())

    // JVM contract: Scanner(File) on a missing file throws FileNotFoundException.
    try {
        Scanner(File(filePath + ".missing"))
        println("missing-file: no throw")
    } catch (failure: FileNotFoundException) {
        println("missing-file: FileNotFoundException")
    }
    try {
        Scanner(Paths.get(filePath + ".missing"))
        println("missing-path: no throw")
    } catch (failure: IOException) {
        println("missing-path: IOException")
    }

    SystemFileSystem.delete(root)
}
