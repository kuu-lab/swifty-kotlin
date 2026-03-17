import java.io.File

fun main() {
    val path = "/tmp/kswiftk_test_readtext.txt"
    val f = File(path)
    try {
        f.writeText("hello\nworld")
        val content = f.readText()
        println(content)
        println(content.length)

        // overwrite
        f.writeText("replaced")
        println(f.readText())

        // appendText
        f.appendText("_tail")
        println(f.readText())
    } finally {
        f.delete()
    }
}
