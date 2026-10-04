@Deprecated(
    "Use newApi()",
    ReplaceWith("newApi()", "golden.diff.newApi", "kotlin.io.path.*")
)
fun oldApi(): Int = 1

fun newApi(): Int = 2

fun main() {
    println("stdlib_kotlin_ReplaceWith_n_n ok")
}
