package golden.sema
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
fun checkFamily(): Int {
    val index = kotlin.collections.checkIndexOverflow(0)
    val count = kotlin.collections.checkCountOverflow(0)
    return index + count
}
