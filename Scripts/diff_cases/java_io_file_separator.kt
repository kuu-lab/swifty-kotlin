import java.io.File

fun main() {
    println(File.separator)
    println(File.separatorChar)
    println(File.pathSeparator)
    println(File.pathSeparatorChar)
    val f = File("/tmp/kuu4440_file_sep.txt")
    println(f.path)
    println(File.separator + "tmp" + File.separator + "x")
    println("a${File.separatorChar}b")
    println("p${File.pathSeparatorChar}q")
}
