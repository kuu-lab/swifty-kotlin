// KSP-992: generic Iterable single-family declarations.

fun probe(values: Iterable<String?>) {
    val single: String? = values.single()
    val singlePredicate: String? = values.single { it != null }
    val singleOrNull: String? = values.singleOrNull()
    val singleOrNullPredicate: String? = values.singleOrNull { it == null }
    println(single)
    println(singlePredicate)
    println(singleOrNull)
    println(singleOrNullPredicate)
}
