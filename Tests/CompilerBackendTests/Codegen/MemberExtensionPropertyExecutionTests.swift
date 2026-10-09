#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct MemberExtensionPropertyExecutionTests {
    @Test(arguments: [false, true])
    func getterSetterCarryBothReceivers(fromSource: Bool) throws {
        let source = try diffCaseSource("member_extension_property_receivers.kt")
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "MemberExtensionPropertyReceivers",
                inputs: [path], outputPath: output, emit: .executable,
                target: defaultTargetTriple(),
                allowDefaultStdlibLibrary: !fromSource
            )
            let ctx = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "12\n9\n20\n24\n14\nscore=7\n9\n10\n11\n13\n20\n24\n10\nscore=11\n13\n14\n15\n22\n42\n46\n24\n")
        }
    }

    @Test
    func importedGettersAndSettersCarryBothReceivers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func compile(_ source: String, module: String, emit: EmitMode, searchPaths: [String] = []) throws -> String {
            let input = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [input], outputPath: output, emit: emit,
                searchPaths: searchPaths, target: defaultTargetTriple(),
                includeStdlib: emit == .executable, allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            if emit == .executable { try LinkPhase().run(ctx) }
            return emit == .library ? output + ".kklib" : output
        }

        let library = try compile("""
        package properties
        open class Holder(protected val off: Int) {
            protected var stored: Int = 0
            fun readStored(): Int = stored
            val Int.score: Int get() = this + off
            var Int.total: Int
                get() = this + off + stored
                set(value) { stored = value - this - off }
        }
        """, module: "PropertyLibrary", emit: .library)
        let metadata = try String(contentsOfFile: library + "/metadata.bin", encoding: .utf8)
        let property = try #require(MetadataDecoder().decode(metadata).first {
            $0.fqName == "properties.Holder.total"
        })
        #expect(property.isMemberExtension)

        let executable = try compile("""
        import properties.Holder
        class Derived : Holder(10) {
            fun use() {
                println(2.score)
                3.total = 20
                3.total += 4
                println(3.total)
                println(readStored())
            }
        }
        fun main() { Derived().use() }
        """, module: "PropertyConsumer", emit: .executable, searchPaths: [library])
        let result = try CommandRunner.run(executable: executable, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == "12\n24\n11\n")
    }

}
#endif
