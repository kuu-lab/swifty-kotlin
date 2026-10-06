#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct WhenSubjectDeclarationCodegenTests {
    @Test func typedSubjectsPreserveOutputAndRepresentation() throws {
        try assertKotlinOutput(
            """
            fun input(): Int? = 7
            fun main() {
                println(when (val missing: Int? = null) {
                    null -> "literal"
                    else -> "other"
                })
                println(when (val value: Int? = input()) {
                    null -> 0
                    else -> value + 1
                })
                println(when (val value: Long = 42) { else -> value })
                println(when (val value: Any = 42L) {
                    is Long -> value + 1L
                    else -> 0L
                })
                println(when (val value: Long? = Long.MIN_VALUE) {
                    null -> "null"
                    else -> "present"
                })
                println(when (val action: (Int) -> Int = { it + 1 }) {
                    is (Int) -> Int -> action(2)
                    else -> 0
                })
                println(when (val value: Long = 42) {
                    in 40L..45L -> value
                    else -> 0L
                })
            }
            """,
            moduleName: "WhenTypedSubjects",
            expected: "literal\n8\n42\n43\npresent\n3\n42\n"
        )
    }
}
#endif
