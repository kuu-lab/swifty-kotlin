// KUU-4593: A definitely-null `!!` operand must throw NullPointerException,
// not KotlinNothingValueException.
fun main() {
    var nn: String? = "hello"
    nn = null
    try {
        println(nn!!.length)
    } catch (e: NullPointerException) {
        println("npe")
    }
}
