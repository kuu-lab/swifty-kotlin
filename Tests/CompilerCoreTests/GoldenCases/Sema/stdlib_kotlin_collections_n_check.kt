package golden.sema

fun checkFamily(): Int {
    val index = kotlin.collections.checkIndexOverflow(0)
    val count = kotlin.collections.checkCountOverflow(0)
    return index + count
}
