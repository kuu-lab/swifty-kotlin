#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-187 (KSP-500): `generateSequence` seed/next-function results and
/// `sequence { yield(value) }` builder arguments were not boxed for primitive
/// element types, so `Char`/`Double`/`Int`/`Boolean`/enum values leaked as raw
/// ordinal/code-point integers and `Double` null terminators were mis-boxed as
/// `-0.0`, producing infinite sequences.

@Suite
struct CodegenBackendGenerateSequencePrimitiveBoxingTests {

    @Test
    func testGenerateSequenceCharBoxesSeedAndNullableNextResult() throws {
        let source = """
        fun main() {
            println(generateSequence('A') { null }.toList())
            println(generateSequence('A') { if (it == 'A') 'B' else null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceChar",
            expected:
                """
                [A]
                [A, B]
                """
                + "\n"
        )
    }

    @Test
    func testGenerateSequenceDoubleBoxesNullableNextResult() throws {
        let source = """
        fun main() {
            println(generateSequence(1.5) { if (it == 1.5) 2.5 else null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceDouble",
            expected: "[1.5, 2.5]\n"
        )
    }

    @Test
    func testGenerateSequenceIntBoxesNullableNextResult() throws {
        let source = """
        fun main() {
            println(generateSequence(1) { if (it < 3) it + 1 else null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceInt",
            expected: "[1, 2, 3]\n"
        )
    }

    @Test
    func testGenerateSequenceZeroSeedIsNotNull() throws {
        let source = """
        fun main() {
            println(generateSequence(0) { null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceZero",
            expected: "[0]\n"
        )
    }

    @Test
    func testGenerateSequenceEnumBoxesSeedAndNullableNextResult() throws {
        let source = """
        enum class Direction { NORTH }

        fun main() {
            println(generateSequence(Direction.NORTH) { null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceEnum",
            expected: "[NORTH]\n"
        )
    }

    @Test
    func testGenerateSequenceNoArgTerminatesOnNull() throws {
        let source = """
        fun main() {
            println(generateSequence { null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceNoArg",
            expected: "[]\n"
        )
    }

    @Test
    func testSequenceBuilderYieldsPrimitiveCharsAndDoubles() throws {
        let source = """
        fun main() {
            println(sequence { yield('X'); yield('Y') }.toList())
            println(sequence { yield(1.5); yield(2.5) }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceBuilderPrimitives",
            expected:
                """
                [X, Y]
                [1.5, 2.5]
                """
                + "\n"
        )
    }
}
#endif
