fun sum(vararg xs: Int) = xs.sum()
fun forward(vararg xs: Int) = sum(*xs) * 10
fun mixed(vararg xs: Int) = sum(0, *xs, 100)
fun strs(vararg xs: String) = xs.joinToString(",")
fun fwdStrs(vararg xs: String) = strs("a", *xs, "z")

fun main() {
    println(forward(1, 2, 3))
    println(forward())
    println(mixed(1, 2, 3))
    println(mixed())
    println(fwdStrs("x", "y"))
    println(fwdStrs())
}
