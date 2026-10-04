// KUU-960: collection HOF lambdas must accept nullable results.
// Transform/selector contracts like (T) -> R have an unbounded R, so a
// nullable lambda body (e.g. Throwable.message: String?) is legal and the
// inferred element type keeps its nullability.

fun main() {
    val cause = IllegalStateException("cause")
    cause.addSuppressed(IllegalArgumentException("other"))
    val suppressed: List<Throwable> = cause.suppressedExceptions

    // Minimal repro: previously rejected with KSWIFTK-TYPE-0001.
    println(suppressed.map { it.message })
    println(suppressed.map { it.cause })

    // Same unbounded-result transform contract on sibling HOFs.
    println(suppressed.mapIndexed { index, e -> "$index:${e.message}" })
    println(suppressed.groupBy { it.message }.keys)
    println(suppressed.sortedBy { it.message }.map { it.message })
    println(suppressed.associateBy { it.message }.keys)
    println(suppressed.associateWith { it.message }.keys)
    println(suppressed.zip(listOf(1)) { e, i -> "${e.message}:$i" })
    println(suppressed.sortedWith(compareBy<Throwable> { it.message }).map { it.message })

    // Nullable element type is preserved by inference.
    val names: List<String?> = suppressed.map { it.message }
    println(names)
}
