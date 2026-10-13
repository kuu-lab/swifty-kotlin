// KUU-1597 Sema owner: pin raw multiline String literal and trimIndent extension typing; literal contents stay in Scripts/diff_cases/raw_string_basic.kt.
fun main() {
    val simple: String = """hello world"""
    val multiline: String = """
        line1
        line2
    """.trimIndent()
}
