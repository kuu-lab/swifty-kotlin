// CANDIDATE-ONLY: runtime resource helpers have no JVM reference; backend
// execution coverage stages the resource under an isolated runtime root.
import java.lang.getSystemClassLoader
import kotlin.io.resourceExists
import kotlin.io.readResourceAsText

fun main() {
    val loader = getSystemClassLoader()
    val path = loader.getResource("Scripts/diff_cases/hello.txt")
    val stream = loader.getResourceAsStream("Scripts/diff_cases/hello.txt")
    val exists = resourceExists("Scripts/diff_cases/hello.txt")
    val text = readResourceAsText("Scripts/diff_cases/hello.txt")
    val first = stream?.read()

    println(path?.endsWith("/Scripts/diff_cases/hello.txt") == true)
    println(stream != null)
    println(exists)
    println(text)
    println(first)
    stream?.close()
}
