#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCharCompareToTests {

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

    // PARITY-CODEGEN-005: Char.compareTo(Char)
    @Test
    func testCodegenCompilesCharCompareTo() throws {
        let source = """
        fun main() {
            println('Z'.compareTo('A'))
            println('A'.compareTo('Z'))
            println('A'.compareTo('A'))
            val erased: Any = 'z'
            println((erased as Char).code)
            println((erased as Char).compareTo('a'))
        }
        """
        try assertKotlinOutput(source, moduleName: "CharCompareTo", expected: "1\n-1\n0\n122\n1\n")
    }

    @Test
    func testCodegenCharCompareToNormalizesUTF16Boundaries() throws {
        let source = #"""
        fun compareChars(lhs: Char, rhs: Char): Int = lhs.compareTo(rhs)

        fun main() {
            println(Char.MAX_VALUE.compareTo(Char.MIN_VALUE))
            println(Char.MIN_VALUE.compareTo(Char.MAX_VALUE))
            println(Char.MAX_VALUE.compareTo(Char.MAX_VALUE))
            println(compareChars('\u7FFF', '\u8000'))
            println(compareChars('\uD800', '\uDC00'))
            println(compareChars('\uDFFF', '\uD800'))
            println(compareChars('\uD800', '\uD800'))
            println('z' - 'a')
            println(Char.MAX_VALUE - Char.MIN_VALUE)
            println('a' < 'z')
            println(Char.MAX_VALUE > Char.MIN_VALUE)
        }
        """#
        try assertKotlinOutput(
            source,
            moduleName: "CharCompareToBoundaries",
            expected: "1\n-1\n0\n-1\n-1\n1\n0\n25\n65535\ntrue\ntrue\n"
        )
    }

    @Test
    func testCodegenCharCompareToDistinguishesGenericDispatch() throws {
        let source = """
        fun <T : Comparable<T>> compareGeneric(lhs: T, rhs: T): Int = lhs.compareTo(rhs)
        fun compareComparable(lhs: Comparable<Char>, rhs: Char): Int = lhs.compareTo(rhs)
        fun asComparable(value: Char): Comparable<Char> = value

        fun main() {
            println('z'.compareTo('a'))
            val comparable: Comparable<Char> = asComparable('z')
            println(comparable.compareTo('a'))
            println(comparable)
            println(compareComparable(comparable, 'a'))
            println(compareGeneric('z', 'a'))
            println(compareGeneric('a', 'z'))
            println(compareGeneric(Char.MAX_VALUE, Char.MIN_VALUE))
            println(compareGeneric(Char.MIN_VALUE, Char.MAX_VALUE))
            println(compareGeneric('a', 'a'))
            println(compareComparable('z', 'a'))
            println(compareGeneric(122, 97))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "CharCompareToGeneric",
            expected: "1\n25\nz\n25\n25\n-25\n65535\n-65535\n0\n25\n1\n"
        )
    }

    // KUU-1211: a `Comparable<Char>` local that never escapes keeps kotlinc's
    // unboxed `char` slot, so `compareTo` reports normalized -1/0/1 like
    // `Intrinsics.compare`; once it escapes to `Any`, reads are boxed and
    // `Comparable.compareTo` reports the raw UTF-16 code-unit difference.
    @Test
    func testCodegenComparableCharLocalEscapeAnalysis() throws {
        let source = """
        fun compareComparable(value: Comparable<Char>): Int = value.compareTo('a')

        fun unescaped() {
            val value: Comparable<Char> = 'z'
            println(value.compareTo('a'))
            println(value.compareTo('z'))
            println(value.compareTo('x'))
        }

        fun escaped() {
            val value: Comparable<Char> = 'z'
            println(value.compareTo('a'))
            println(value)
            println(compareComparable(value))
        }

        fun main() {
            unescaped()
            escaped()
            val nullable: Comparable<Char>? = 'z'
            println(nullable?.compareTo('a'))
            val copySource: Comparable<Char> = 'z'
            val copyTarget = copySource
            println(copySource.compareTo('a'))
            println(copyTarget.compareTo('a'))
            println(copyTarget)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ComparableCharLocalEscape",
            expected: "1\n0\n1\n25\nz\n25\n1\n25\n25\nz\n"
        )
    }
}
#endif
