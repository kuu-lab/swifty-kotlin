// SKIP-DIFF (DEBT-DIFF-001): kswiftc resolves the kotlin.io.Reader.readText() extension, but
// provides no way to construct a java.io.Reader (no java.io.StringReader, and
// File.bufferedReader() was removed by CLEANUP-STUB-107), so the call cannot be exercised
// end-to-end here.
import java.io.Reader

fun describe(reader: Reader): String = reader.readText()

fun main() {
    println("ok")
}
