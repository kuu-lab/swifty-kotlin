fun main() {
    // KUU-3789: the vararg element's expected type (Long) must contextualize
    // the bare integer literal through the collection-factory fast path, the
    // same way it already does for mutableSetOf. Without it the literal stays
    // Int-boxed and a later Long unbox throws.
    val mutable = mutableListOf<Long>(1)
    println((mutable[0] as Any) is Long)
    mutable[0]--
    println(mutable[0])
    val arrayList = arrayListOf<Long>(1)
    println((arrayList[0] as Any) is Long)
    val notNull = listOfNotNull<Long>(1)
    println((notNull[0] as Any) is Long)
    // Mixed integer literals: a non-literal input infers the element type and
    // the constants widen to it, so mutableListOf(1, 1L) is MutableList<Long>.
    val inferred = mutableListOf(1, 1L)
    println((inferred[0] as Any) is Long)
    inferred[0]--
    println(inferred[0])
    val inferredArrayList = arrayListOf(1, 1L)
    println((inferredArrayList[0] as Any) is Long)
}
