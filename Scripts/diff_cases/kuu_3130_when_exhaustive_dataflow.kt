// KUU-3130: enum entries excluded by a preceding terminating branch
// (`return`/`throw`) must not be required by a following `when`
// (DataFlowBasedExhaustiveness). Minimized from JetBrains
// codegen/box/when/exhaustiveness/exhaustiveWithNegativeEnum.kt.

enum class MiniState { A, B, C }

fun selected(value: MiniState): Int {
    if (value == MiniState.A) return 1
    return when (value) {
        MiniState.B -> 2
        MiniState.C -> 3
    }
}

fun selectedSequential(value: MiniState): Int {
    if (value == MiniState.A) return 1
    if (value == MiniState.B) return 2
    return when (value) {
        MiniState.C -> 3
    }
}

fun selectedThrow(value: MiniState): Int {
    if (value == MiniState.A) throw IllegalStateException("a")
    return when (value) {
        MiniState.B -> 2
        MiniState.C -> 3
    }
}

fun selectedNotEqual(value: MiniState): Int {
    if (value != MiniState.A) return when (value) {
        MiniState.B -> 2
        MiniState.C -> 3
    }
    return 1
}

fun box(): String {
    val results = listOf(
        selected(MiniState.B),
        selectedSequential(MiniState.C),
        selectedThrow(MiniState.C),
        selectedNotEqual(MiniState.B),
    )
    return if (results == listOf(2, 3, 3, 2)) "OK" else "FAIL $results"
}

fun main() {
    print(box())
}
