// KUU-3964 / KT-72035: a reified type argument inferred to an intersection is
// rejected — the mixed builtin join keeps its Comparable/Serializable conjuncts
// instead of collapsing to bare Comparable<*> or Number.
fun main() {
    arrayOf("a", 1)
    arrayOf("a", null, 1)
    arrayOf(1, 1.5)
}
