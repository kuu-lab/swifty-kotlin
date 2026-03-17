import java.io.File

fun main() {
    val base = File("/tmp/kswiftk_test_mkdirs")
    val nested = File("/tmp/kswiftk_test_mkdirs/a/b/c")
    val file = File("/tmp/kswiftk_test_mkdirs/a/b/c/hello.txt")
    try {
        // mkdirs creates intermediate directories
        println(nested.mkdirs())   // true
        println(nested.exists())   // true
        println(nested.isDirectory) // true

        // second call returns false (already exists)
        println(nested.mkdirs())   // false

        // create a file inside
        file.writeText("content")
        println(file.exists())    // true

        // delete file
        println(file.delete())    // true
        println(file.exists())    // false

        // delete empty leaf directory
        println(nested.delete())  // true
        println(nested.exists())  // false

        // mkdir (single level) succeeds because parent "b" still exists
        val fresh = File("/tmp/kswiftk_test_mkdirs/a/b/c")
        println(fresh.mkdir())    // true
    } finally {
        // cleanup remaining dirs
        File("/tmp/kswiftk_test_mkdirs/a/b/c").delete()
        File("/tmp/kswiftk_test_mkdirs/a/b").delete()
        File("/tmp/kswiftk_test_mkdirs/a").delete()
        base.delete()
    }
}
