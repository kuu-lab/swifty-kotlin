#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendComparableUserDefinedClassEdgeCasesTests {

    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenComparisonOperatorsDispatchUserDefinedCompareToThroughGenericBound() throws {
        let source = """
        class Version(val major: Int, val minor: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int {
                val byMajor = major.compareTo(other.major)
                return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
            }
        }

        fun <T : Comparable<T>> larger(a: T, b: T): T = if (a >= b) a else b

        fun main() {
            val v1 = Version(1, 2)
            val v2 = Version(1, 5)
            println(v1 < v2)
            println(v1 > v2)
            println(larger(v1, v2).minor)
            println(larger(v2, v1).minor)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonOperatorsUserDefinedCompareToThroughGenericBound",
            expected:
                """
                true
                false
                5
                5

                """
        )
    }

    // BUG-170 / BUG-226: through an erased `T : Comparable<T>` bound the
    // operands can have different runtime types (subclass vs base, or two
    // classes sharing a Comparable interface). Dispatch must still reach the
    // user `compareTo` instead of comparing heap addresses — including when
    // compareTo is only an interface default (Bronze/Gold) and allocation
    // order is reversed.
    @Test
    func testCodegenComparisonOperatorsDispatchCompareToAcrossRelatedRuntimeTypes() throws {
        let source = """
        interface Ranked : Comparable<Ranked> {
            val rank: Int
            override fun compareTo(other: Ranked): Int = rank.compareTo(other.rank)
        }

        class Bronze : Ranked {
            override val rank: Int = 1
        }

        class Gold : Ranked {
            override val rank: Int = 3
        }

        open class Animal : Comparable<Animal> {
            open fun weight(): Int = 10
            override fun compareTo(other: Animal): Int = weight().compareTo(other.weight())
        }

        class Elephant : Animal() {
            override fun weight(): Int = 100
        }

        fun <T : Comparable<T>> larger(a: T, b: T): T = if (a >= b) a else b

        fun main() {
            val bronze: Ranked = Bronze()
            val gold: Ranked = Gold()
            println(larger(bronze, gold).rank)
            println(larger(gold, bronze).rank)

            val goldFirst: Ranked = Gold()
            val bronzeSecond: Ranked = Bronze()
            println(larger(bronzeSecond, goldFirst).rank)
            println(larger(goldFirst, bronzeSecond).rank)

            val animal: Animal = Animal()
            val elephant: Animal = Elephant()
            println(larger(animal, elephant).weight())
            println(larger(elephant, animal).weight())
            println(animal < elephant)
            println(elephant < animal)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonOperatorsCompareToAcrossRelatedRuntimeTypes",
            expected:
                """
                3
                3
                3
                3
                100
                100
                true
                false

                """
        )
    }

    // BUG-224: identical to the scenario above, but with `gold` declared (and
    // therefore heap-allocated) before `bronze`. Before the fix, dispatch for
    // `compareTo` reached only through an interface's default implementation
    // (never through an override on the constructed class or a class
    // superclass) fell back to comparing raw heap addresses instead of
    // calling `compareTo` — a bug that stayed silent on macOS with the
    // original declaration order (Darwin's allocator happened to place
    // `bronze` below `gold`) and only surfaced on Linux/glibc, whose
    // allocator orders them the other way. Swapping the declaration order
    // reverses the relative heap addresses on macOS too, making this variant
    // fail deterministically pre-fix and pass deterministically post-fix,
    // independent of platform allocator behavior.
    @Test
    func testCodegenComparisonOperatorsDispatchCompareToThroughInterfaceDefaultRegardlessOfDeclarationOrder() throws {
        let source = """
        interface Ranked : Comparable<Ranked> {
            val rank: Int
            override fun compareTo(other: Ranked): Int = rank.compareTo(other.rank)
        }

        class Bronze : Ranked {
            override val rank: Int = 1
        }

        class Gold : Ranked {
            override val rank: Int = 3
        }

        fun <T : Comparable<T>> larger(a: T, b: T): T = if (a >= b) a else b

        fun main() {
            val gold: Ranked = Gold()
            val bronze: Ranked = Bronze()
            println(larger(bronze, gold).rank)
            println(larger(gold, bronze).rank)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonOperatorsCompareToInterfaceDefaultSwappedDeclarationOrder",
            expected:
                """
                3
                3

                """
        )
    }

    @Test
    func testCodegenComparableMaxOfMinOfDispatchUserDefinedCompareTo() throws {
        let source = """
        class Version(val major: Int, val minor: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int {
                val byMajor = major.compareTo(other.major)
                return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
            }
            override fun toString(): String = "$major.$minor"
        }

        fun main() {
            val v1 = Version(1, 2)
            val v2 = Version(1, 5)
            println(maxOf(v1, v2))
            println(minOf(v1, v2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparableMaxOfMinOfUserDefinedCompareTo",
            expected:
                """
                1.5
                1.2

                """
        )
    }
}
#endif
