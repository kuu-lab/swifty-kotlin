// SKIP-DIFF (DEBT-DIFF-007): ref fails only because this file is missing `@OptIn(ExperimentalContracts::class)`
// (test-input bug); candidate fails separately with a real bug: `returns()`/`implies()` inside `contract { }`
// resolve to KSWIFTK-SEMA-0002 "No viable overload found" instead of the ContractBuilder members registered
// in HeaderHelpers.registerSyntheticContractStubs. See docs/diff-skip-inventory.md (DEBT-DIFF-007) for details.
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
