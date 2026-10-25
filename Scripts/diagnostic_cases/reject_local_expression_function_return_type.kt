// EXPECT-REJECT
fun main() {
    fun value(): Int = { 1 }
    value()
}
