// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
import kotlin.contracts.contract

fun requireNotNullText(value: String?) {
    contract {
        returns() implies (value != null)
    }
    if (value == null) {
        throw Exception("missing")
    }
}

fun main() {
    val text: String? = "hello"
    requireNotNullText(text)
    println(text.length)
}
