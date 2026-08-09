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
struct CodegenBackendDefaultParameterValuesTests {
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

    @Test func testTopLevelFunctionDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        fun foo(x: Simple = Simple()): Int = x.n
        fun main() {
            println(foo())
        }
        """
        try assertKotlinOutput(source, moduleName: "DefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testTopLevelFunctionDefaultValueReadsCompanionProperty() throws {
        let source = """
        class Bar(val tag: String) {
            companion object {
                val Def: Bar = Bar("default")
            }
        }
        fun greet(b: Bar = Bar.Def): String = b.tag
        fun main() {
            println(greet())
        }
        """
        try assertKotlinOutput(source, moduleName: "DefaultValueCompanionPropertyRead", expected: "default\n")
    }

    @Test func testMemberFunctionDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        class Holder {
            fun foo(x: Simple = Simple()): Int = x.n
        }
        fun main() {
            println(Holder().foo())
        }
        """
        try assertKotlinOutput(source, moduleName: "MemberDefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testPrimaryConstructorDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        class Holder(val payload: Simple = Simple())
        fun main() {
            println(Holder().payload.n)
        }
        """
        try assertKotlinOutput(source, moduleName: "PrimaryCtorDefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testSecondaryConstructorDefaultValueConstructsClassInstance() throws {
        let source = """
        class Simple(val n: Int = 9)
        class Holder {
            val payload: Simple
            constructor(x: Simple = Simple()) {
                payload = x
            }
        }
        fun main() {
            println(Holder().payload.n)
        }
        """
        try assertKotlinOutput(source, moduleName: "SecondaryCtorDefaultValueConstructorCall", expected: "9\n")
    }

    @Test func testDefaultValueExpressionMayReferenceEarlierParameter() throws {
        let source = """
        fun foo(a: Int, b: Int = a + 1): Int = a + b
        fun main() {
            println(foo(10))
        }
        """
        try assertKotlinOutput(source, moduleName: "DefaultValueReferencesEarlierParameter", expected: "21\n")
    }
}
#endif
