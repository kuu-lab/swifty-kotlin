// SKIP-DIFF (DEBT-DIFF-001): kotlin.io.resourceExists / readResourceAsText and the
// java.lang top-level classloader helpers are KSwiftK surface additions; JVM kotlinc
// cannot resolve them, and the harness does not stage classpath resources anyway.
import java.lang.getSystemClassLoader
import kotlin.io.resourceExists
import kotlin.io.readResourceAsText

fun main() {
    val loader = getSystemClassLoader()
    val path = loader.getResource("hello.txt")
    val stream = loader.getResourceAsStream("hello.txt")
    val exists = resourceExists("hello.txt")
    val text = readResourceAsText("hello.txt")
    val first = stream?.read()
    stream?.close()
}
