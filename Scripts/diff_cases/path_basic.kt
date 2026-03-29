import kotlin.io.path.Path

fun main() {
    val tmpDir = "/tmp/kswiftk_path_test_" + System.currentTimeMillis()
    val dir = Path(tmpDir)
    dir.createDirectories()
    println(dir.exists())       // true
    println(dir.isDirectory())  // true

    val file = dir.resolve("hello.txt")
    file.writeText("hello\nworld")
    println(file.exists())        // true
    println(file.isRegularFile()) // true
    println(file.name)            // hello.txt

    val content = file.readText()
    println(content)

    val lines = file.readLines()
    println(lines.size)  // 2
    for (line in lines) {
        println(line)
    }

    println(file.toString())

    val parent = file.parent
    if (parent != null) {
        println(parent.toString() == tmpDir)  // true
    }

    val resolved = dir.resolve(Path("sub"))
    println(resolved.toString())

    // normalize
    val p = Path("/foo/bar/../baz")
    println(p.normalize().toString())  // /foo/baz

    // fileName property (returns Path)
    val fileNamePath = file.fileName
    println(fileNamePath.toString())  // hello.txt

    // root property
    val absPath = Path("/usr/local/bin")
    val root = absPath.root
    if (root != null) {
        println(root.toString())  // /
    }

    // nameCount
    println(absPath.nameCount)  // 3

    // startsWith / endsWith
    val base = Path("/usr/local")
    println(absPath.startsWith(base))              // true
    println(absPath.startsWith("/usr/local"))       // true
    println(absPath.endsWith(Path("local/bin")))    // true
    println(absPath.endsWith("bin"))                // true

    // relativize
    val rel = base.relativize(absPath)
    println(rel.toString())  // bin

    // toFile
    val javaFile = file.toFile()
    println(javaFile.exists())  // true

    // cleanup
    file.deleteIfExists()
    println(file.exists())  // false
    dir.deleteIfExists()
}
