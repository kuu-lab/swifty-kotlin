import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_file_basic_test.txt")

    // parent should be non-null
    println(f.parent != null)  // true

    // File(parent, child) constructor
    val f2 = File("/tmp", "kswiftk_file_basic_test2.txt")
    println(f2.name) // kswiftk_file_basic_test2.txt

    println("done")
}
