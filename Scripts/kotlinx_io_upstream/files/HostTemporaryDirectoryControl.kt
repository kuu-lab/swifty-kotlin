import kotlinx.io.files.SystemTemporaryDirectory
import kotlinx.io.files.SystemPathSeparator

// Fresh-process controlled environment/native host reference determines expected output.
fun main() {
    println("temporary:$SystemTemporaryDirectory")
    println("separator:$SystemPathSeparator")
}
