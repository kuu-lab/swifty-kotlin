// DIFF_CANDIDATE_ONLY: Kotlin/Native 2.3.10 prints TODO; JVM adds a stack location.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kotlin_test_todo.expected
// Reference: https://github.com/JetBrains/kotlin/blob/v2.3.10/kotlin-native/runtime/src/main/kotlin/kotlin/test/Assertions.kt
import kotlin.test.*

fun main() {

    var calls = 0
    todo { calls++; throw IllegalStateException("must not run") }
    println(calls)
}
