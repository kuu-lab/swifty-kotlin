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
        }
        """
        try assertKotlinOutput(source, moduleName: "CharCompareTo", expected: "1\n-1\n0\n")
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

        fun main() {
            println('z'.compareTo('a'))
            val comparable: Comparable<Char> = 'z'
            println(comparable.compareTo('a'))
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
            expected: "1\n1\n25\n-25\n65535\n-65535\n0\n25\n1\n"
        )
    }
}
#endif
