open class Foo(open val x: Boolean)
class Bar : Foo(false) { val y = "OK" }

fun contract(value: Foo) = value
fun contract(value: String) = value
fun contract(value: String, suffix: Boolean) = value
fun identity(value: String) = value

fun box(): String {
    val temp = if (true) contract(Bar()) else Bar()
    val oneArgumentResult: String = contract("OK")
    val twoArgumentResult: String = contract("OK", false)
    val renamedResult: String = identity("OK")
    return (temp as Bar).y + if (oneArgumentResult == twoArgumentResult && oneArgumentResult == renamedResult) "" else "FAIL"
}

fun main() {
    println(box())
}
