@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-2298: the bundled JVM Comparator maps its generic method parameters
    /// to platform types, while source-declared Kotlin interfaces stay strict.
    @Test
    func testNullableArraySlotsMatchJvmComparatorPlatformParameters() throws {
        let comparatorDeclaration = """
        package kotlin
        public fun interface Comparator<in T> {
            public fun compare(a: T, b: T): Int
        }
        """
        let source = """
        import kotlin.Comparator

        private fun <T> compareNullable(value: T?, comparator: Comparator<T>): Int =
            comparator.compare(value, value)

        private fun <T> greater(array: Array<T?>, i: Int, j: Int, comparator: Comparator<T>? = null): Boolean {
            if (comparator != null) return comparator.compare(array[i], array[j]) > 0
            return false
        }

        private fun <T> compareNonNullSlot(array: Array<T>, comparator: Comparator<T>): Int =
            comparator.compare(array[0], array[0])

        private fun <T> compareAssertedSlot(array: Array<T?>, comparator: Comparator<T>): Int =
            comparator.compare(array[0]!!, array[0]!!)

        private fun <T> compareNullableComparator(array: Array<T?>, comparator: Comparator<T?>): Int =
            comparator.compare(array[0], array[0])
        """
        let artifactPath = try buildMinimalComparatorStdlibArtifact(comparatorDeclaration)
        defer { try? FileManager.default.removeItem(atPath: artifactPath) }

        for (surface, libraryPath) in [("bundled source", nil), ("fresh .kklib", artifactPath)] {
            for level in [OptimizationLevel.O0, .O2] {
                let contents = libraryPath == nil ? [comparatorDeclaration, source] : [source]
                try withTemporaryFiles(contents: contents) { inputs in
                    let context = makeComparatorCompilationContext(
                        inputs: inputs,
                        stdlibLibraryPath: libraryPath,
                        optLevel: level
                    )
                    defer {
                        try? FileManager.default.removeItem(atPath: context.options.outputPath + ".o")
                    }
                    if libraryPath == nil {
                        _ = context.sourceManager.addFile(
                            path: inputs[0], contents: Data(comparatorDeclaration.utf8), origin: .bundledStdlib
                        )
                    }
                    try runToKIR(context)
                    #expect(
                        !context.diagnostics.hasError,
                        "Unexpected diagnostics with \(surface) at \(level): \(context.diagnostics.diagnostics)"
                    )

                    let sema = try #require(context.sema)
                    let comparator = try #require(sema.symbols.lookup(
                        fqName: ["kotlin", "Comparator", "compare"].map(context.interner.intern)
                    ))
                    let signature = try #require(sema.symbols.functionSignature(for: comparator))
                    #expect(sema.types.nullability(of: signature.parameterTypes[0]) == .platformType)
                    #expect(sema.types.nullability(of: signature.parameterTypes[1]) == .platformType)

                    try LoweringPhase().run(context)
                    try CodegenPhase().run(context)
                }
            }
        }

        let negativeControl = """
        import kotlin.Comparator

        private interface LocalComparator<T> {
            fun compare(a: T, b: T): Int
        }
        private fun <T> rejected(value: T?, comparator: LocalComparator<T>): Int =
            comparator.compare(value, value)
        """
        for (surface, libraryPath) in [("bundled source", nil), ("fresh .kklib", artifactPath)] {
            let contents = libraryPath == nil ? [comparatorDeclaration, negativeControl] : [negativeControl]
            try withTemporaryFiles(contents: contents) { inputs in
                let context = makeComparatorCompilationContext(
                    inputs: inputs,
                    stdlibLibraryPath: libraryPath,
                    optLevel: .O0
                )
                if libraryPath == nil {
                    _ = context.sourceManager.addFile(
                        path: inputs[0], contents: Data(comparatorDeclaration.utf8), origin: .bundledStdlib
                    )
                }
                try? runSema(context)
                #expect(
                    context.diagnostics.diagnostics.filter { $0.severity == .error }.count == 1
                        && context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" },
                    "The Kotlin source interface must remain strict with \(surface): \(context.diagnostics.diagnostics)"
                )
                let sema = try #require(context.sema)
                let localComparator = try #require(sema.symbols.lookup(
                    fqName: ["LocalComparator", "compare"].map(context.interner.intern)
                ))
                let signature = try #require(sema.symbols.functionSignature(for: localComparator))
                #expect(sema.types.nullability(of: signature.parameterTypes[0]) == .nonNull)
            }
        }
    }

    /// KUU-2225: Java and Kotlin Comparator names share one contravariant SAM type.
    @Test
    func testJavaUtilComparatorAliasPreservesTypeIdentityAndVarianceAcrossStdlibSurfaces() throws {
        let source = """
        import java.util.Comparator
        import kotlin.Comparator as KotlinComparator

        private class Record(val key: Int)

        private fun compareAsJava(comparator: Comparator<Record>): Int =
            comparator.compare(Record(1), Record(2))

        private fun compareAsKotlin(comparator: KotlinComparator<Record>): Int =
            comparator.compare(Record(1), Record(2))

        fun main() {
            val javaComparator = Comparator<Record> { left, right -> left.key.compareTo(right.key) }
            val kotlinComparator: KotlinComparator<Record> = javaComparator
            val javaAgain: Comparator<Record> = kotlinComparator
            println(compareAsJava(kotlinComparator))
            println(compareAsKotlin(javaAgain))

            val broadJava: Comparator<Any> = Comparator<Any> { _, _ -> -7 }
            val narrowKotlin: KotlinComparator<Record> = broadJava
            println(narrowKotlin.compare(Record(1), Record(2)))

            val broadKotlin: KotlinComparator<Any> = KotlinComparator<Any> { _, _ -> -9 }
            val narrowJava: Comparator<Record> = broadKotlin
            println(narrowJava.compare(Record(1), Record(2)))
        }
        """
        let expected = "-1\n-1\n-7\n-9\n"
        let artifactPath = try Self.buildStdlibArtifact()

        for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] {
            for optimizationLevel in [OptimizationLevel.O0, .O2] {
                let output = try runJavaUtilComparatorConsumer(
                    source,
                    moduleName: "KUU2225Comparator_\(surface)_\(optimizationLevel.rawValue)",
                    stdlibLibraryPath: libraryPath,
                    optLevel: optimizationLevel
                )
                #expect(
                    output == expected,
                    "Unexpected output using \(surface) at \(optimizationLevel): \(String(reflecting: output))"
                )
            }
        }
    }
}

private func makeComparatorCompilationContext(
    inputs: [String],
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel
) -> CompilationContext {
    CompilationContext(
        options: CompilerOptions(
            moduleName: "KUU2298Comparator_\(optLevel.rawValue)",
            inputs: inputs,
            outputPath: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .object,
            target: defaultTargetTriple(),
            optLevel: optLevel,
            includeStdlib: false,
            stdlibLibraryPath: stdlibLibraryPath,
            allowDefaultStdlibLibrary: false
        ),
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
}

private func buildMinimalComparatorStdlibArtifact(_ comparatorSource: String) throws -> String {
    var artifactPath: String?
    try withTemporaryFile(contents: comparatorSource) { inputPath in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: "KSwiftKStdlib",
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .library,
                target: defaultTargetTriple(),
                includeStdlib: false,
                stdlibOnly: true,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        _ = context.sourceManager.addFile(
            path: inputPath, contents: Data(comparatorSource.utf8), origin: .bundledStdlib
        )
        try runToKIR(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        artifactPath = outputBase + ".kklib"
    }
    return try #require(artifactPath)
}

private func runJavaUtilComparatorConsumer(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel
) throws -> String {
    var output = ""
    try withTemporaryFile(contents: source) { inputPath in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: outputBase) }

        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(context)
        try assertNoDiagnosticErrors(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        try LinkPhase().run(context)

        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        guard result.exitCode == 0 else {
            throw TestCompilationFailure(
                description: "Execution failed with exit \(result.exitCode): \(result.stderr)"
            )
        }
        output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
    }
    return output
}
