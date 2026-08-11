#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite
struct CodegenBackendMatchGroupCollectionTests {
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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    // STDLIB-TEXT-TYPE-008: MatchGroupCollection interface — index access, named access, size
    @Test func testMatchGroupCollectionIndexAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)")
            val m = r.find("hello-world")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(1)?.value)
            println(m?.groups?.get(2)?.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionIndex",
            expected:
                """
                hello-world
                hello
                world
                """ + "\n"
        )
    }

    @Test func testMatchGroupCollectionNamedAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find("2025-06-09")
            println(m?.groups?.get("year")?.value)
            println(m?.groups?.get("month")?.value)
            println(m?.groups?.get("day")?.value)
            println(m?.groups?.get("missing"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionNamed",
            expected:
                """
                2025
                06
                09
                null
                """ + "\n"
        )
    }

    @Test func testMatchGroupCollectionSize() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)-(\\\\w+)")
            val m = r.find("a-b-c")
            println(m?.groups?.size)
            val r2 = Regex("\\\\w+")
            val m2 = r2.find("hello")
            println(m2?.groups?.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionSize",
            expected:
                """
                4
                1
                """ + "\n"
        )
    }

    // Regression for constructor-call lowering: Regex(pattern) must flatten
    // its String argument and call the __kk_regex_create_flat factory directly.
    @Test func testRegexConstructionFromStringLiteralAndBasicUse() throws {
        let source = """
        fun main() {
            val r = Regex("\\\\w+")
            println(r.containsMatchIn("hello world"))
            println(r.matches("hello"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexConstructionAndUse",
            expected:
                """
                true
                true
                """ + "\n"
        )
    }

    @Test func testMatchGroupCollectionOutOfBoundsReturnsNull() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\d+)")
            val m = r.find("42")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(99))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionOutOfBounds",
            expected:
                """
                42
                null
                """ + "\n"
        )
    }
}
#endif
