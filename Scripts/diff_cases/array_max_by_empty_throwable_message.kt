// KUU-2579: Reading Throwable.message after empty Array.maxBy throws must dispatch through the Throwable vtable.
fun main() {
    try {
        emptyArray<String>().maxBy { it.length }
    } catch (error: NoSuchElementException) {
        println(error.message == null)
    }
}
