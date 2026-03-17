import java.io.File

fun main() {
    val dir = File("/tmp/kswiftk_test_exists_dir")
    val file = File("/tmp/kswiftk_test_exists_dir/test.txt")
    val missing = File("/tmp/kswiftk_test_exists_nonexistent")
    try {
        dir.mkdirs()
        file.writeText("data")

        println(dir.exists())       // true
        println(dir.isDirectory)    // true
        println(dir.isFile)         // false

        println(file.exists())     // true
        println(file.isFile)       // true
        println(file.isDirectory)  // false

        println(missing.exists())     // false
        println(missing.isFile)       // false
        println(missing.isDirectory)  // false
    } finally {
        file.delete()
        dir.delete()
    }
}
