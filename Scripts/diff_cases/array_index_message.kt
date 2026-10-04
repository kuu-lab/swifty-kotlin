// ArrayIndexOutOfBoundsException messages match the JVM.
fun main() {
    val a = arrayOf(1, 2, 3)
    try { a[5] } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { a[-1] = 0 } catch (e: IndexOutOfBoundsException) { println(e.message) }
    try { intArrayOf(1, 2, 3)[5] } catch (e: IndexOutOfBoundsException) { println(e.message) }
}
