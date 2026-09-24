// KSP-1351: generic Sequence last-family declarations.

fun probe(values: Sequence<String?>) {
    val last: String? = values.last()
    val lastPredicate: String? = values.last { it != null }
    val lastOrNull: String? = values.lastOrNull()
    val lastOrNullPredicate: String? = values.lastOrNull { it == null }
    println(last)
    println(lastPredicate)
    println(lastOrNull)
    println(lastOrNullPredicate)
}
