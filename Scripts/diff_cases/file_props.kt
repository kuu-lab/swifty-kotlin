import java.io.File

fun main() {
    val f = File("/tmp/test_props.txt")
    println(f.name)        // "test_props.txt"
    println(f.path)        // "/tmp/test_props.txt"
    println(f.exists())    // false
    println(f.isFile)      // false
    println(f.isDirectory) // false

    val d = File("/tmp")
    println(d.name)        // "tmp"
    println(d.path)        // "/tmp"
    println(d.exists())    // true
    println(d.isDirectory) // true
    println(d.isFile)      // false

    // KSP-483: File path pure-logic layer
    println(File("Main.kt").extension)
    println(File("archive.tar.gz").extension)
    println(File("README").extension)
    println(File(".bashrc").extension)

    println(File("Main.kt").nameWithoutExtension)
    println(File("archive.tar.gz").nameWithoutExtension)
    println(File("README").nameWithoutExtension)

    println(File("/a/b/c.txt").parent)
    println(File("relative.txt").parent)
    println(File("a/b").parent)

    println(File("/a/b").invariantSeparatorsPath)
    println(File("a/b/c").invariantSeparatorsPath)

    println(File("/a/b").isRooted)
    println(File("a/b").isRooted)

    println(File("/a/b/c").startsWith(File("/a/b")))
    println(File("/a/b/c").startsWith(File("/a/x")))
    println(File("/a/b/c").startsWith("/a/b"))
    println(File("/a/b/c").startsWith("/a/x"))

    println(File("/a/b/c.txt").resolveSibling("d.txt").path)
    println(File("/a/b/c.txt").resolveSibling(File("d.txt")).path)
    println(File("c.txt").resolveSibling("d.txt").path)

    println(File("/a/b/c").toRelativeString(File("/a")))
    println(File("/a/b").toRelativeString(File("/a/b/c")))
    println(File("/a/b").toRelativeString(File("/a/b")))
    try {
        File("relative").toRelativeString(File("/a"))
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("toRelativeString-threw")
    }

    println(File("/a/./b/../c").normalize().path)
    println(File("a/../../b").normalize().path)
    println(File("./a/b").normalize().path)
}
