// KOTLINC_FLAGS: -Xreturn-value-checker=full

@IgnorableReturnValue
fun compute(): Int = 42

fun main() {
    compute()
    println("ok")
}
