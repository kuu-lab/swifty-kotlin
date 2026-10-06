// KUU-1326: Throwable API parity with Kotlin/JVM.
fun main() {
    val primary: Throwable = RuntimeException("primary")
    val empty: Array<Throwable> = primary.suppressed
    println(empty.size)
    val first = IllegalStateException("first")
    primary.addSuppressed(first)
    val snapshot: Array<Throwable> = primary.suppressed
    println(snapshot.size)
    println(snapshot[0] === first)
    snapshot[0] = Exception("replacement")
    println(primary.suppressed[0].message)
    primary.addSuppressed(IllegalArgumentException("second"))
    println(snapshot.size)
    println(primary.suppressed.size)
    println(primary.suppressed[1].message)
    println(primary.getSuppressed().size)
    println(primary.suppressedExceptions.size)
    println(RuntimeException("subtype").suppressed.size)
}
