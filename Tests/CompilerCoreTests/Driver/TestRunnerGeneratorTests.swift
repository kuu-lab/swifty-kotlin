@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct TestRunnerGeneratorTests {
    private let annotations = """
    package kotlin.test
    annotation class Test
    annotation class Ignore
    annotation class BeforeTest
    annotation class AfterTest
    annotation class BeforeClass
    annotation class AfterClass
    """

    private func discover(_ source: String) throws -> (CompilationContext, TestRunnerGenerator.Result?) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let annotationPath = directory.appendingPathComponent("annotations.kt").path
        let input = directory.appendingPathComponent("tests.kt").path
        let options = CompilerOptions(moduleName: "Discovery", inputs: [annotationPath, input],
                                      outputPath: directory.appendingPathComponent("runner").path,
                                      emit: .executable, target: defaultTargetTriple(), includeStdlib: false)
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: [
            annotationPath: Data(annotations.utf8), input: Data(source.utf8),
        ]).context
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let generated = context.diagnostics.hasError ? nil : TestRunnerGenerator(context: context).generate()
        return (context, generated)
    }

    @Test
    func resolvesAliasesAndExcludesUnrelatedAnnotations() throws {
        let (context, generated) = try discover("""
        import kotlin.test.Test as ActualTest
        @Test fun unrelated() {}
        @ActualTest private fun `actual test`() {}
        annotation class Test
        fun main() { unrelated() }
        """)
        let result = try #require(generated)
        let runner = String(decoding: try #require(result.sources[result.runnerPath]), as: UTF8.self)
        #expect(runner.contains("__kswiftk_test_case_"))
        let userPath = context.options.inputs.last!
        let original = String(decoding: context.sourceManager.contents(of: context.sourceManager.fileID(forPath: userPath)!), as: UTF8.self)
        let overlay = String(decoding: try #require(result.sources[userPath]), as: UTF8.self)
        #expect(!original.contains("fun __kswiftk_test_case_"))
        #expect(overlay.contains("`actual test`()"))
        #expect(!overlay.contains("__kswiftk_test_reporter.pass(\"unrelated [tests.kt]\")"))
        #expect(overlay.contains("fun main() { unrelated() }"))
    }

    @Test(arguments: [
        "import kotlin.test.Test as Case\n@Test fun unrelated() {}\n@Case fun real() {}",
        "import kotlin.test.*\nclass Suite { annotation class Test; @Test fun unrelated() {}; @kotlin.test.Test fun real() {} }",
    ])
    func respectsLexicalAndImportScope(source: String) throws {
        let (_, generated) = try discover(source)
        let result = try #require(generated)
        let overlays = result.sources.values.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        #expect(overlays.contains(".pass(\"real [tests.kt]\")") || overlays.contains(".pass(\"Suite.real\")"))
        #expect(!overlays.contains(".pass(\"unrelated [tests.kt]\")"))
        #expect(!overlays.contains(".pass(\"Suite.unrelated\")"))
    }

    @Test(arguments: [
        "@kotlin.test.Test fun invalid(value: Int) {}",
        "@kotlin.test.BeforeClass fun invalid(value: Int) {}",
        "@kotlin.test.AfterClass fun invalid(): Int = 1",
        "@kotlin.test.BeforeClass suspend fun invalid() {}",
        "@kotlin.test.AfterClass fun <T> invalid() {}",
        "@kotlin.test.BeforeClass fun String.invalid() {}",
        "class Invalid { companion object { @kotlin.test.BeforeClass fun invalid(value: Int) {} } }",
        "@kotlin.test.Ignore object Invalid { @kotlin.test.AfterClass fun invalid(): Int = 1; @kotlin.test.Test fun test() {} }",
        "@kotlin.test.Test fun invalid(): Int = 1",
        "@kotlin.test.Test suspend fun invalid() {}",
        "@kotlin.test.Test fun <T> invalid() {}",
        "@kotlin.test.Test fun String.invalid() {}",
        "@kotlin.test.Ignore @kotlin.test.Test fun invalid(value: Int) {}",
        "class Invalid private constructor() { @kotlin.test.Test fun test() {} }",
        "class Invalid(val value: Int) { @kotlin.test.Test fun test() {} }",
        "class Invalid<T> { @kotlin.test.Test fun test() {} }",
        "class Owner { private class Invalid { @kotlin.test.Test fun test() {} } }",
    ])
    func rejectsUnsupportedDeclarations(source: String) throws {
        let (context, result) = try discover(source)
        #expect(result == nil)
        #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TEST-0001" && $0.primaryRange != nil })
    }

    @Test
    func inheritedTestsGetBodyForBodylessClassAndIgnoredSuiteNeedsNoConstructor() throws {
        let (_, generated) = try discover("""
        import kotlin.test.*
        abstract class Base { @Test open fun inherited() {} }
        class Derived: Base();
        @Ignore class Ignored private constructor() { @Test fun ignored() {} }
        """)
        let result = try #require(generated)
        let overlays = result.sources.values.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        #expect(overlays.contains("class Derived: Base() {"))
        #expect(overlays.contains("\"Ignored.ignored\""))
        #expect(overlays.contains("reporter.skip("))
        #expect(!overlays.contains("`Ignored`()"))
        var options = CompilerOptions(moduleName: "Overlay", inputs: Array(result.sources.keys).sorted(), outputPath: "/tmp/overlay",
                                      emit: .executable, target: defaultTargetTriple(), includeStdlib: false)
        options.entryPointFQName = TestRunnerGenerator.entryPoint
        let overlay = CompilationContext(options: options, sourceManager: SourceManager(),
                                         diagnostics: DiagnosticEngine(), interner: StringInterner())
        for path in options.inputs { _ = overlay.sourceManager.addFile(path: path, contents: result.sources[path]!) }
        try runFrontendSyntaxPhases(overlay)
        #expect(!overlay.diagnostics.hasError, "\(overlay.diagnostics.diagnostics)\n\(overlays)")
    }

    @Test
    func resolvesSuiteHookAliasesAndWarnsOnInstancePlacement() throws {
        let (context, generated) = try discover("""
        import kotlin.test.*
        import kotlin.test.BeforeClass as BeforeSuite
        import kotlin.test.AfterClass as AfterSuite
        annotation class BeforeClass
        class Suite {
            @kotlin.test.BeforeClass fun misplaced() {}
            companion object Named {
                @BeforeSuite private fun setup() {}
                @AfterSuite private fun cleanup() {}
                @BeforeClass fun unrelated() {}
            }
            @Test fun test() {}
        }
        """)
        let result = try #require(generated)
        let runner = String(decoding: try #require(result.sources[result.runnerPath]), as: UTF8.self)
        #expect(runner.contains("__kswiftk_test_BeforeClass_suite_"))
        #expect(runner.contains("__kswiftk_test_AfterClass_suite_"))
        let overlays = result.sources.values.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        #expect(overlays.contains("`Suite`.`Named`.__kswiftk_test_bridge_"))
        #expect(overlays.contains("{ `setup`() }"))
        #expect(overlays.contains("{ `cleanup`() }"))
        #expect(!overlays.contains("{ `misplaced`() }"))
        #expect(!overlays.contains("{ `unrelated`() }"))
        let warnings = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-TEST-0002" }
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
        #expect(warnings.first?.primaryRange != nil)
    }

    @Test
    func ignoredAndEmptySuitesDoNotGenerateClassHookCalls() throws {
        let (_, generated) = try discover("""
        import kotlin.test.*
        @Ignore class Ignored private constructor() {
            companion object { @BeforeClass fun setup() {}; @AfterClass fun cleanup() {} }
            @Test fun test() {}
        }
        object AllIgnored {
            @BeforeClass fun setup() {}
            @AfterClass fun cleanup() {}
            @Test @Ignore fun test() {}
        }
        object Empty { @BeforeClass fun setup() {}; @AfterClass fun cleanup() {} }
        @BeforeClass fun setup() {}
        @AfterClass fun cleanup() {}
        @Test @Ignore fun ignoredFileTest() {}
        """)
        let result = try #require(generated)
        let runner = String(decoding: try #require(result.sources[result.runnerPath]), as: UTF8.self)
        #expect(!runner.contains("__kswiftk_test_BeforeClass_"))
        #expect(!runner.contains("__kswiftk_test_AfterClass_"))
        #expect(runner.components(separatedBy: "reporter.skip(").count - 1 == 3)
    }

    @Test(arguments: [
        ("@Test @Ignore", "@Test", false),
        ("@Test", "@Ignore", false),
        ("@Test @Ignore", "", true),
        ("@Test", "@Test @Ignore", true),
    ])
    func inheritedIgnoreUsesNearestTestDeclaration(baseTags: String, overrideTags: String, ignored: Bool) throws {
        let (_, generated) = try discover("""
        import kotlin.test.*
        abstract class Base { \(baseTags) open fun test() {} }
        class Derived: Base() {
            companion object { @BeforeClass fun setup() {}; @AfterClass fun cleanup() {} }
            \(overrideTags) override fun test() {}
        }
        """)
        let result = try #require(generated)
        let runner = String(decoding: try #require(result.sources[result.runnerPath]), as: UTF8.self)
        #expect(runner.contains("reporter.skip(\"Derived.test\")") == ignored)
        #expect(runner.contains("__kswiftk_test_BeforeClass_suite_") == !ignored)
        #expect(runner.contains("__kswiftk_test_AfterClass_suite_") == !ignored)
    }

    @Test(arguments: ["", "Hidden"], ["private", "protected"])
    func bridgesHiddenCompanionsFromTheirOriginalClassScope(companionName: String, visibility: String) throws {
        let (_, generated) = try discover("""
        import kotlin.test.*
        class Suite {
            \(visibility) companion object \(companionName) {
                @BeforeClass private fun setup() {}
                @AfterClass private fun cleanup() {}
            }
            @Test fun test() {}
        }
        """)
        let result = try #require(generated)
        let overlays = result.sources.values.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        #expect(overlays.contains("\(visibility) companion object \(companionName)"))
        #expect(overlays.contains("object __kswiftk_test_suite_hooks_suite_"))
        #expect(overlays.contains("`Suite`.__kswiftk_test_suite_hooks_suite_"))
        #expect(overlays.contains("fun before(): Unit"))
        #expect(overlays.contains("fun after(): Unit"))
    }

    @Test
    func entrySelectionChangesIncrementalConfiguration() {
        var options = CompilerOptions(moduleName: "Entry", inputs: ["test.kt"], outputPath: "/tmp/test-runner",
                                      emit: .executable, target: defaultTargetTriple(), includeStdlib: false)
        let cache = IncrementalCompilationCache(cachePath: "/tmp/unused-test-runner-cache")
        let original = cache.buildConfigurationHash(for: options)
        options.entryPointFQName = TestRunnerGenerator.entryPoint
        #expect(original != cache.buildConfigurationHash(for: options))
    }
}
