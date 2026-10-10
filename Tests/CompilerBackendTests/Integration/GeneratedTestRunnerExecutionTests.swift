@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct GeneratedTestRunnerExecutionTests {
    private func compileAndRun(_ sources: [(String, String)], fromSource: Bool) throws -> CommandResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputs = try sources.map { name, source in
            let path = directory.appendingPathComponent(name)
            try source.write(to: path, atomically: true, encoding: .utf8)
            return path.path
        }
        let output = directory.appendingPathComponent("runner").path
        let options = CompilerOptions(moduleName: "GeneratedTests", inputs: inputs, outputPath: output,
                                      emit: .executable, target: defaultTargetTriple(), frontendFlags: ["generate-test-runner"],
                                      allowDefaultStdlibLibrary: !fromSource)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        for (index, source) in sources.enumerated() {
            #expect(try String(contentsOfFile: inputs[index], encoding: .utf8) == source.1)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("__kswiftk_test_runner.kt").path))
        do {
            return try CommandRunner.run(executable: output, arguments: [])
        } catch CommandRunnerError.nonZeroExit(let result) {
            return result
        }
    }

    @Test(arguments: [false, true])
    func discoversAcrossFilesAndPreservesLifecycleAndEntry(fromSource: Bool) throws {
        let sourceA = """
        package runner
        import kotlin.test.*
        import kotlin.test.Test as Case
        var starts: Int = 0
        fun start(): Int { starts += 1; println("init"); return starts }
        val initialized: Int = start()
        abstract class Base {
            @BeforeTest private fun before() { println("base.before") }
            @AfterTest private fun after() { println("base.after") }
            @Case open fun test() { println("base.test") }
        }
        class Derived: Base() { override fun test() { println("derived.test") } }
        class DerivedIgnore: Base() { @Ignore override fun test() { fail("must not run") } }
        class Fresh(val number: Int = 7) {
            var local: Int = 0
            @BeforeTest @Ignore private fun setup() { local += 1 }
            @Case fun a() { assertEquals(1, local); assertEquals(7, number); println("fresh.a") }
            @Case fun b() { assertEquals(1, local); println("fresh.b") }
            @AfterTest private fun cleanup() { println("fresh.after") }
        }
        class Secondary {
            constructor() { println("secondary.ctor") }
            @Case fun one() {}
        }
        object Singleton {
            var count: Int = 0
            @Case fun a() { count += 1; assertEquals(1, count) }
            @Case fun b() { count += 1; assertEquals(2, count) }
        }
        interface Holder { object Nested { @Case fun one() { assertTrue(runner.Holder.Nested === Holder.Nested) } } }
        class Lexical {
            annotation class Test
            @Test fun unrelated() { fail("must not discover") }
            @Case fun real() {}
        }
        @Ignore class Skipped private constructor() {
            init { fail("must not construct") }
            @Case fun one() {}
        }
        @Case private fun fileTest() { assertEquals(1, initialized); assertEquals(1, starts); println("file.a") }
        fun main() { println("USER MAIN") }
        """
        let sourceB = """
        package runner
        import kotlin.test.Test as Case
        import kotlin.test.BeforeTest
        import kotlin.test.AfterTest
        annotation class Test
        @Test fun unrelated() { println("UNRELATED") }
        @BeforeTest fun beforeFile() { println("file.before") }
        @AfterTest fun afterFile() { println("file.after") }
        @Case private fun fileTest() { println("file.b") }
        @Case @kotlin.test.Ignore fun ignored() { println("IGNORED") }
        @Case private fun `日本語`() { println("unicode") }
        """
        let result = try compileAndRun([("b.kt", sourceB), ("a.kt", sourceA)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        init
        base.before
        derived.test
        base.after
        PASS runner.Derived.test
        SKIP runner.DerivedIgnore.test
        fresh.a
        fresh.after
        PASS runner.Fresh.a
        fresh.b
        fresh.after
        PASS runner.Fresh.b
        PASS runner.Holder.Nested.one
        PASS runner.Lexical.real
        secondary.ctor
        PASS runner.Secondary.one
        PASS runner.Singleton.a
        PASS runner.Singleton.b
        SKIP runner.Skipped.one
        file.a
        PASS runner.fileTest [a.kt]
        file.before
        file.b
        file.after
        PASS runner.fileTest [b.kt]
        SKIP runner.ignored [b.kt]
        file.before
        unicode
        file.after
        PASS runner.日本語 [b.kt]
        Tests: 11 passed, 0 failed, 3 skipped

        """)
    }

    @Test(arguments: [false, true])
    func reportsFailuresContinuesAndAttemptsEveryCleanup(fromSource: Bool) throws {
        let result = try compileAndRun([("failure.kt", """
        package failures
        import kotlin.test.*
        class AAssertion {
            @Test fun failTest() { fail("assertion") }
            @AfterTest fun cleanup() { println("assertion.cleanup") }
        }
        class BBefore {
            fun println(message: String) { throw IllegalStateException("must not call user printer") }
            @BeforeTest fun first() { throw IllegalStateException("before") }
            @BeforeTest fun second() { kotlin.io.println("NEVER BEFORE") }
            @Test fun test() { kotlin.io.println("NEVER TEST") }
            @AfterTest fun firstAfter() { kotlin.io.println("before.cleanup") }
            @AfterTest fun secondAfter() { throw IllegalStateException("after") }
        }
        class CConstructor {
            init { throw IllegalStateException("constructor") }
            @Test fun test() {}
            @AfterTest fun cleanup() { println("NEVER CLEANUP") }
        }
        class DAfter {
            @Test fun test() {}
            @AfterTest fun first() { println("after.cleanup") }
            @AfterTest fun second() { throw IllegalStateException("after only") }
        }
        class EPass { @Test fun test() {} }
        class FSkip { @Test @Ignore fun test() { fail("NEVER") } }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 1)
        #expect(result.stdout == """
        assertion.cleanup
        FAIL failures.AAssertion.failTest: assertion
        AFTER failures.BBefore.test: after
        before.cleanup
        FAIL failures.BBefore.test: before
        FAIL failures.CConstructor.test: constructor
        after.cleanup
        FAIL failures.DAfter.test: after only
        PASS failures.EPass.test
        SKIP failures.FSkip.test
        Tests: 1 passed, 4 failed, 1 skipped

        """)
    }

    @Test
    func importsDefaultPackageWrappersAndRunsAnEmptySuite() throws {
        let result = try compileAndRun([("root.kt", """
        import kotlin.test.*
        class Root { @Test private fun `private test`() { assertTrue(true) } }
        @Test private fun topLevel() { assertEquals(3, 3) }
        fun main() { println("USER MAIN") }
        """)], fromSource: false)
        #expect(result.exitCode == 0)
        #expect(result.stdout == "PASS Root.private test\nPASS topLevel [root.kt]\nTests: 2 passed, 0 failed, 0 skipped\n")
        let empty = try compileAndRun([("empty.kt", "fun main() { println(\"USER MAIN\") }")], fromSource: false)
        #expect(empty.exitCode == 0)
        #expect(empty.stdout == "Tests: 0 passed, 0 failed, 0 skipped\n")
    }
}
