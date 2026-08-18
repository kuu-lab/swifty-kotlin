@Deprecated("Use newFun instead", level = DeprecationLevel.WARNING)
fun oldFun(): Int = 1

@Deprecated("Use replacement", replaceWith = ReplaceWith("newFun()"))
fun oldWithReplace(): Int = 2

fun newFun(): Int = 3

fun main() {
    println(oldFun())
    println(oldWithReplace())
    println(newFun())
    println("stdlib_kotlin_n_Deprecated ok")
}
