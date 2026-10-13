// JAVA_FLAGS: -Dfile.encoding=UTF-8
import java.nio.charset.Charset

// forName must initialize Charsets even before any constant is read by main.
fun main() {
    println(Charset.forName("utf8").name())
    val latin = Charset.forName("ISO-8859-1")
    println(latin.name())
    println("é".toByteArray(latin).toString(latin))
}
