@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2238: java.util.Date keeps one public type identity in source and artifact modes.
    @Test
    func testJavaUtilDateIdentityThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let javaDateSurface = """
        import java.util.Date

        fun identity(date: Date): Date = date
        fun qualifiedIdentity(date: java.util.Date): java.util.Date = identity(date)
        fun main() {}
        """
        let localDateControl = """
        class Date
        fun identity(date: Date): Date = date
        fun main() {}
        """
        let dateFacadePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CompilerCore/Stdlib/java/util/Date.kt").path
        #expect(FileManager.default.fileExists(atPath: dateFacadePath))

        func makeContext(
            inputs: [String],
            moduleName: String,
            emit: EmitMode,
            outputPath: String,
            optLevel: OptimizationLevel,
            searchPaths: [String] = [],
            stdlibLibraryPath: String? = nil
        ) -> CompilationContext {
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: inputs,
                outputPath: outputPath,
                emit: emit,
                searchPaths: searchPaths,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: false,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            )
            return CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
        }

        let libraryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let libraryPath = libraryBase + ".kklib"
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }
        let dateLibrary = makeContext(
            inputs: [dateFacadePath],
            moduleName: "JavaUtilDateSurfaceLibrary",
            emit: .library,
            outputPath: libraryBase,
            optLevel: .O0
        )
        try CompilerTestSupport.runToKIR(dateLibrary)
        try LoweringPhase().run(dateLibrary)
        try assertNoDiagnosticErrors(dateLibrary)
        try CodegenPhase().run(dateLibrary)
        #expect(FileManager.default.fileExists(atPath: libraryPath + "/metadata.bin"))

        for level in [OptimizationLevel.O0, .O2] {
            try withTemporaryFile(contents: javaDateSurface) { input in
                let output = input + ".source"
                let context = makeContext(
                    inputs: [dateFacadePath, input],
                    moduleName: "JavaUtilDateSourceSurface",
                    emit: .kirDump,
                    outputPath: output,
                    optLevel: level,
                    stdlibLibraryPath: nil
                )
                try CompilerTestSupport.runToKIR(context)
                try LoweringPhase().run(context)
                try assertNoDiagnosticErrors(context)
            }

            try withTemporaryFile(contents: javaDateSurface) { input in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeContext(
                    inputs: [input],
                    moduleName: "JavaUtilDateArtifactSurface",
                    emit: .executable,
                    outputPath: output,
                    optLevel: level,
                    searchPaths: [libraryPath]
                )
                try CompilerTestSupport.runToKIR(context)
                try LoweringPhase().run(context)
                try assertNoDiagnosticErrors(context)
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                #expect(FileManager.default.fileExists(atPath: output))
            }
        }

        try withTemporaryFile(contents: localDateControl) { input in
            let output = input + ".local"
            let context = makeContext(
                inputs: [input],
                moduleName: "JavaUtilDateLocalControl",
                emit: .kirDump,
                outputPath: output,
                optLevel: .O0,
                stdlibLibraryPath: nil
            )
            try CompilerTestSupport.runToKIR(context)
            try LoweringPhase().run(context)
            try assertNoDiagnosticErrors(context)
        }
    }
}
