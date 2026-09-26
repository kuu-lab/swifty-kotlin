// SKIP-DIFF (DEBT-DIFF-001): java.io.BufferedReader / InputStreamReader / System.`in`
// are not resolvable by kswiftc (no construction path in the bundled surface), so the
// call cannot be exercised end-to-end here.
import java.io.BufferedReader
import java.io.InputStreamReader

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`))
    println("line: ${reader.readLine()}")
}
