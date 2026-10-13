package rejectedcontract
fun choose(value: Int): String = "top-string"
class Priority {
    fun choose(value: Int): Int = 1
    fun check() { val result: String = choose(1) }
}
fun Priority.choose(value: Int): String = "extension-string"
