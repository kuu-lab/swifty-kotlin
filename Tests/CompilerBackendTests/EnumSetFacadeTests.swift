@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct EnumSetFacadeTests {
    @Test
    func enumSetContractsAcrossStdlibSurfaces() throws {
        let artifactDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("kuu-2067-stdlib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: artifactDirectory) }
        let artifact = try StdlibArtifactBuilder.build(
            outputBase: artifactDirectory.appendingPathComponent("stdlib").path,
            target: CompilerTestSupport.defaultTargetTriple()
        )
        print("EnumSet contract: fresh stdlib \(artifact)")
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let behavior = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/java_enum_set_none_of.kt"
        ), encoding: .utf8)
        let expected = """
        0
        true
        true
        true
        false
        true
        ONE,TWO,THREE
        true
        true
        ONE,THREE
        true
        THREE
        ONE
        THREE
        true
        true
        0
        false
        0
        true
        true
        true
        wrong enum
        null element
        false
        false
        TWO
        null class
        non-enum class
        true
        true
        false
        one
        one
        null

        """
        let accepted = [
            // Keep the issue's exact independent reproducer and HashSet control.
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            fun empty(type: java.lang.Class<Kind>): MutableSet<Kind> = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            enum class Kind { ONE, TWO }
            fun empty(): MutableSet<Kind> = HashSet<Kind>()
            fun main() {}
            """,
            """
            import java.util.*
            enum class Kind { ONE, TWO }
            fun empty(type: java.lang.Class<Kind>): EnumSet<Kind> = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            enum class Kind { ONE, TWO }
            fun empty(type: java.lang.Class<Kind>): java.util.EnumSet<Kind> = java.util.EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            fun empty(type: java.lang.Class<Kind>?): EnumSet<Kind> = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            import java.util.EnumSet
            fun <E : Enum<E>> empty(type: java.lang.Class<E>): MutableSet<E> = EnumSet.noneOf(type)
            fun main() {}
            """,
        ]
        let rejected = [
            """
            import java.util.EnumSet
            fun empty(type: java.lang.Class<String>) = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            enum class Other { ONE }
            fun wrong(type: java.lang.Class<Kind>): MutableSet<Other> = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            fun wrong(type: java.lang.Class<Kind>): EnumSet<String> = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            fun wrong(type: java.lang.Class<Kind>) {
                val set: MutableSet<Kind> = EnumSet.noneOf(type)
                set.add(null)
            }
            fun main() {}
            """,
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            fun wrong(type: java.lang.Class<Kind>): EnumSet<Kind?> = EnumSet.noneOf(type)
            fun main() {}
            """,
            """
            import java.util.EnumSet
            enum class Kind { ONE, TWO }
            enum class Other { ONE }
            fun wrong(type: java.lang.Class<Kind>) { EnumSet.noneOf(type).add(Other.ONE) }
            fun main() {}
            """,
            """
            enum class Kind { ONE, TWO }
            fun wrong(type: java.lang.Class<Kind>) = EnumSet.noneOf(type)
            fun main() {}
            """,
        ]

        for library in [nil, Optional(artifact)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                print("EnumSet contract: \(library == nil ? "source" : "artifact") \(optimization)")
                // Batch independent files to inject the bundled stdlib once per gate.
                try compileEnumSetConsumers(accepted, library: library, optimization: optimization) { context, _ in
                    try assertNoDiagnosticErrors(context)
                    try LoweringPhase().run(context)
                    try CodegenPhase().run(context)
                    try LinkPhase().run(context)
                }
                try compileEnumSetConsumers(rejected, library: library, optimization: optimization) { context, paths in
                    for (index, path) in paths.enumerated() {
                        let errors = context.diagnostics.diagnostics.filter {
                            $0.severity == .error && $0.primaryRange.map {
                                context.sourceManager.path(of: $0.start.file) == path
                            } == true
                        }
                        #expect(!errors.isEmpty, "Expected rejection: \(rejected[index])")
                        if rejected[index].contains("import java.util.EnumSet") {
                            #expect(!errors.contains {
                                $0.code == "KSWIFTK-SEMA-0024" || $0.message.contains("Unresolved reference 'EnumSet'")
                            },
                                    "The rejection must validate the contract after resolving the import")
                        }
                    }
                }
                try compileEnumSetConsumers([behavior], library: library, optimization: optimization) { context, _ in
                    try assertNoDiagnosticErrors(context)
                    try LoweringPhase().run(context)
                    try CodegenPhase().run(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: context.options.outputPath, arguments: [])
                    #expect(result.exitCode == 0, "\(result.stderr)")
                    #expect(result.stdout == expected, "library=\(String(describing: library)) optimization=\(optimization)")
                }
            }
        }
    }
}

private func compileEnumSetConsumers(
    _ sources: [String],
    library: String?,
    optimization: OptimizationLevel,
    check: (CompilationContext, [String]) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try sources.enumerated().map { index, source in
        let path = directory.appendingPathComponent("Consumer\(index).kt").path
        // The root file preserves the exact issue reproducer; independent
        // controls use separate packages and retain file-scoped imports.
        let contents = index == 0 ? source : "package control\(index)\n" + source
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
    let output = directory.appendingPathComponent("consumer").path
    let context = CompilationContext(
        options: CompilerOptions(
            moduleName: "EnumSetConsumer", inputs: paths, outputPath: output,
            emit: .executable, target: CompilerTestSupport.defaultTargetTriple(), optLevel: optimization,
            includeStdlib: library == nil, stdlibLibraryPath: library,
            allowDefaultStdlibLibrary: false
        ),
        sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
    )
    try runSema(context)
    if !context.diagnostics.hasError {
        try BuildKIRPhase().run(context)
    }
    try check(context, paths)
}
