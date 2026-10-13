interface HeaderValue { val number: Int }
class HeaderImplementation : HeaderValue { override val number: Int = 42 }
class HeaderDelegate(val name: String)
    : HeaderValue by HeaderImplementation() {
    val other: Int = 7
}
fun main() {
    val value = HeaderDelegate("sample")
    println(value.number)
    println(value.name)
    println(value.other)
}
