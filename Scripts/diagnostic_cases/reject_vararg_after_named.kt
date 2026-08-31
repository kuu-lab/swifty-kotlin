// EXPECT-REJECT
fun varargFun(vararg items: Int, name: String) = name

fun main() {
    varargFun(name = "bad", 1, 2)
}
