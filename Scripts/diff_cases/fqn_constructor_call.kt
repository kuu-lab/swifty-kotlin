fun main() {
    // Fully-qualified top-level function call (kotlin.math.abs). This used
    // to link-fail: KIR lowering tried to evaluate the "kotlin.math"
    // namespace prefix as a real receiver value, referencing an undefined
    // "_math" symbol.
    println(kotlin.math.abs(-7))

    // Fully-qualified constructor call with no arguments, reached through a
    // two-segment namespace path (kotlin.text). This used to fail Sema
    // resolution entirely with "Unresolved reference 'kotlin'".
    val sb = kotlin.text.StringBuilder()
    sb.append("hello")
    sb.append(", ")
    sb.append("world")
    println(sb.toString())

    // Fully-qualified constructor call with arguments, reached through a
    // single-segment namespace path (kotlin). A naive Sema-only fix made
    // this compile and run but silently dropped the last constructor
    // argument and shifted the rest by one slot, printing "(0, 1)" instead
    // of "(1, 2)" -- assert on the actual values, not just that it runs.
    val pair = kotlin.Pair(1, 2)
    println(pair)
    println(pair.first)
    println(pair.second)

    // Fully-qualified annotation-class constructor call.
    val uuidAnnotation = kotlin.uuid.ExperimentalUuidApi()
    println(uuidAnnotation is Annotation)

    // Fully-qualified calls to stdlib vararg factory functions. These take a
    // different KIR lowering path than the unqualified spelling (the
    // resolved-symbol path, not lowerCallExpr's specialized collection-factory
    // pre-check), so pin their output to guard against that path silently
    // diverging from kotlinc in the future.
    println(kotlin.collections.listOf(1, 2, 3))
    val mutable = kotlin.collections.mutableListOf(1, 2, 3)
    mutable.add(4)
    println(mutable)
}
