@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testJavaCollectionsSortAcceptsReadOnlyListThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let source = try diffCaseSource("java_util_collections_sort_list_parameter.kt", file: #filePath)
        let expected = try diffCaseSource("java_util_collections_sort_list_parameter.expected", file: #filePath)
        let artifactPath = try Self.buildStdlibArtifact()
        for libraryPath in [nil, artifactPath] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { input in
                    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: output) }
                    let context = javaCollectionsContext(input: input, output: output, libraryPath: libraryPath, optLevel: optLevel)
                    try runToKIR(context)
                    try assertNoDiagnosticErrors(context)
                    try LoweringPhase().run(context)
                    try CodegenPhase().run(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0, "\(result.stderr)")
                    #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                            "source: \(libraryPath == nil), optimization: \(optLevel)")
                }
            }
        }
    }

    @Test
    func testJavaCollectionsFactoriesAndAlgorithmsThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let source = try diffCaseSource("java_util_collections_factories_algorithms.kt", file: #filePath)
        let expected = try diffCaseSource("java_util_collections_factories_algorithms.expected", file: #filePath)
        let artifactPath = try Self.buildStdlibArtifact()
        for libraryPath in [nil, artifactPath] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { input in
                    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: output) }
                    let context = javaCollectionsContext(input: input, output: output, libraryPath: libraryPath, optLevel: optLevel)
                    try runToKIR(context)
                    try assertNoDiagnosticErrors(context)
                    try LoweringPhase().run(context)
                    try CodegenPhase().run(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0, "\(result.stderr)")
                    #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                            "source: \(libraryPath == nil), optimization: \(optLevel)")
                }
            }
        }
    }

    /// KUU-2059: preserve the four factories' views, mutable mapped returns,
    /// generic constraints, and exceptions through both stdlib routes.
    @Test
    func testJavaCollectionsViewsThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let source = try diffCaseSource("java_util_collections_views.kt", file: #filePath)
        let expected = try diffCaseSource("java_util_collections_views.expected", file: #filePath)
        let artifactPath = try Self.buildStdlibArtifact()
        for libraryPath in [nil, artifactPath] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { input in
                    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: output) }
                    let context = javaCollectionsContext(input: input, output: output, libraryPath: libraryPath, optLevel: optLevel)
                    try runToKIR(context)
                    try assertNoDiagnosticErrors(context)
                    try LoweringPhase().run(context)
                    try CodegenPhase().run(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0, "\(result.stderr)")
                    #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                            "source: \(libraryPath == nil), optimization: \(optLevel)")
                }
            }
        }
    }

    @Test
    func testJavaCollectionsTypeAndVisibilityBoundariesThroughBothRoutes() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let negatives = [
            "fun frozen(values: MutableList<Int>): List<String> = Collections.unmodifiableList(values)",
            "fun frozen(values: MutableSet<Int>): Set<String> = Collections.unmodifiableSet(values)",
            "fun frozen(values: MutableMap<Int, Int>): Map<String, Int> = Collections.unmodifiableMap(values)",
            "fun frozen(values: MutableMap<String, Int>): Map<String, String> = Collections.unmodifiableMap(values)",
            "fun keys(values: MutableMap<String, Int>): MutableSet<String> = Collections.newSetFromMap(values)",
            "fun keys(values: MutableMap<String, Nothing?>) = Collections.newSetFromMap(values)",
            "fun keys(values: MutableMap<String, *>) = Collections.newSetFromMap(values)",
            "fun keys(values: MutableMap<String, in Boolean>) = Collections.newSetFromMap(values)",
            "fun keys(values: MutableMap<String, Boolean>) = Collections.newSetFromMap<Any>(values)",
            "fun frozen(values: List<String>): MutableList<Any?> = Collections.unmodifiableList<String>(values)",
            "fun frozen(values: Set<String>): MutableSet<Any?> = Collections.unmodifiableSet<String>(values)",
            "fun frozen(values: Map<String, Int>): MutableMap<Any?, Any?> = Collections.unmodifiableMap<String, Int>(values)",
            "fun keys(values: MutableMap<String, Boolean>): MutableSet<Any?> = Collections.newSetFromMap<String>(values)",
            "fun keys(values: MutableMap<out String, Boolean>) = Collections.newSetFromMap<String>(values)",
            "fun keys(values: MutableMap<out Int, Boolean>) = Collections.newSetFromMap<Int>(values)",
            "fun keys(values: MutableMap<out Boolean, Boolean>) = Collections.newSetFromMap<Boolean>(values)",
        ]
        for libraryPath in [nil, artifactPath] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                let declarations = negatives.enumerated().map { index, declaration in
                    declaration.replacingOccurrences(of: "fun frozen", with: "fun rejected\(index)")
                        .replacingOccurrences(of: "fun keys", with: "fun rejected\(index)")
                }
                let source = "import java.util.Collections\n" + declarations.joined(separator: "\n") + "\nfun main() {}"
                try withTemporaryFile(contents: source) { input in
                    let context = javaCollectionsContext(input: input, output: input + ".out", libraryPath: libraryPath, optLevel: optLevel)
                    do { try runSema(context) } catch {
                        // Assert diagnostics for every independent declaration.
                    }
                    let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
                    let lines = Set(errors.compactMap { diagnostic -> Int? in
                        guard let location = diagnostic.primaryRange?.start,
                              context.sourceManager.path(of: location.file) == input else { return nil }
                        return context.sourceManager.lineColumn(of: location).line
                    })
                    for index in negatives.indices {
                        #expect(lines.contains(index + 2), "negative \(index) was accepted, source: \(libraryPath == nil): \(errors)")
                    }
                    #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-0022" },
                            "Types must be rejected after resolving the facade: \(errors)")
                }
                let helpers = ["CollectionsUnmodifiableList", "collectionsRejectMutation"]
                let imports = helpers.map { "import java.util.\($0)" }.joined(separator: "\n")
                try withTemporaryFile(contents: imports + "\nfun main() {}") { input in
                    let context = javaCollectionsContext(input: input, output: input + ".out", libraryPath: libraryPath, optLevel: optLevel)
                    do { try runSema(context) } catch {}
                    let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
                    for helper in helpers {
                        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0040" && $0.message.contains(helper) },
                                "private helper \(helper) was imported")
                    }
                }
            }
        }
    }
}

private func javaCollectionsContext(
    input: String,
    output: String,
    libraryPath: String?,
    optLevel: OptimizationLevel = .O0
) -> CompilationContext {
    CompilationContext(
        options: CompilerOptions(
            moduleName: "KUU2059Collections", inputs: [input], outputPath: output,
            emit: .executable, target: defaultTargetTriple(), optLevel: optLevel,
            includeStdlib: libraryPath == nil, stdlibLibraryPath: libraryPath,
            allowDefaultStdlibLibrary: false
        ),
        sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
    )
}
