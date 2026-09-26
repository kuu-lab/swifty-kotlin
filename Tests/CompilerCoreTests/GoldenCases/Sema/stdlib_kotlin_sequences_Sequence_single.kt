// KSP-1357: generic Sequence single-family declarations.

fun probe(values: Sequence<String?>) {
    val single: String? = values.single()
    val singlePredicate: String? = values.single { it != null }
    val singleOrNull: String? = values.singleOrNull()
    val singleOrNullPredicate: String? = values.singleOrNull { it == null }
    println(single)
    println(singlePredicate)
    println(singleOrNull)
    println(singleOrNullPredicate)
}
