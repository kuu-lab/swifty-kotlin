// KUU-4156: kotlin.io.println/print must follow the bundled
// java.lang.System.out stream state like the JVM — closing System.out drops
// later console writes, while System.err.close() leaves stdout alone.
fun main() {
    println("before")
    System.err.close()
    println("after-err-close")
    System.out.close()
    println("dropped-println")
    print("dropped-print")
    println()
    println(42)
    println(null as Any?)
    System.out.println("dropped-system-out")
    println("still-dropped")
}
