package golden.sema

fun useCheckNotNull(value: String?): Int {
    val checked = checkNotNull(value)
    val checkedWithMessage = checkNotNull(value) { "unused" }
    return checked.length + checkedWithMessage.length
}
