// KUU-1597 Sema owner: pin raw multiline String and trimMargin overload resolution; trimmed contents stay in Scripts/diff_cases/trim_margin.kt.
fun main() {
    val defaultMargin: String = """
        |alpha
        |beta
        |gamma
    """.trimMargin()
    val customMargin: String = """
        >left
        >right
    """.trimMargin(">")
}
