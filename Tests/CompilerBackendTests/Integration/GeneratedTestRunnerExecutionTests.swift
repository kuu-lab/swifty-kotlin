@testable import CompilerCore
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
        class DerivedIgnore: Base() { @Ignore override fun test() { println("ignore-only override") } }
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
        base.before
        ignore-only override
        base.after
        PASS runner.DerivedIgnore.test
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
        Tests: 12 passed, 0 failed, 2 skipped

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

    @Test(arguments: [false, true])
    func resolvesWrappersAndSuitesAcrossPackages(fromSource: Bool) throws {
        let result = try compileAndRun([("alpha.kt", """
        package alpha
        import kotlin.test.Test
        class AlphaSuite { @Test fun member() { println("alpha.suite") } }
        @Test fun fileTest() { println("alpha.file") }
        """), ("beta.kt", """
        package beta
        import kotlin.test.Test
        class BetaSuite { @Test fun member() { println("beta.suite") } }
        @Test fun fileTest() { println("beta.file") }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        alpha.suite
        PASS alpha.AlphaSuite.member
        alpha.file
        PASS alpha.fileTest [alpha.kt]
        beta.suite
        PASS beta.BetaSuite.member
        beta.file
        PASS beta.fileTest [beta.kt]
        Tests: 4 passed, 0 failed, 0 skipped

        """)
    }

    @Test(arguments: [false, true])
    func runsClassHooksOnceWithInheritanceFreshInstancesAndIgnoredCases(fromSource: Bool) throws {
        let result = try compileAndRun([("lifecycle.kt", """
        package lifecycle
        import kotlin.test.*
        import kotlin.test.BeforeClass as BeforeSuite
        import kotlin.test.AfterClass as AfterSuite
        var starts: Int = 0
        var finishes: Int = 0
        var bodies: Int = 0
        abstract class Base {
            companion object {
                @BeforeClass fun never() { fail("base companion is not inherited") }
            }
            @BeforeTest private fun before() { println("base.before") }
            @AfterTest private fun after() { println("base.after") }
            @Test open fun a() { println("base.test") }
        }
        class Derived: Base() {
            var local: Int = 0
            companion object Named {
                @BeforeSuite @Ignore private fun setup() {
                    starts += 1; assertEquals(1, starts); println("suite.before")
                }
                @AfterSuite private fun cleanup() {
                    finishes += 1; assertEquals(1, finishes); assertEquals(2, bodies); println("suite.after")
                }
            }
            @BeforeTest private fun before() { local += 1; println("derived.before") }
            override fun a() { assertEquals(1, starts); assertEquals(0, finishes); assertEquals(1, local); bodies += 1; println("a") }
            @Test fun b() { assertEquals(1, starts); assertEquals(0, finishes); assertEquals(1, local); bodies += 1; println("b") }
            @Test @Ignore fun ignored() { fail("ignored") }
            @AfterTest private fun after() { println("derived.after") }
        }
        object AllIgnored {
            @BeforeClass fun setup() { fail("all ignored setup") }
            @AfterClass fun cleanup() { fail("all ignored cleanup") }
            @Test @Ignore fun test() { fail("all ignored test") }
        }
        object Empty { @BeforeClass fun setup() { fail("empty setup") }; @AfterClass fun cleanup() { fail("empty cleanup") } }
        @Ignore class Skipped private constructor() {
            companion object { @BeforeClass fun setup() { fail("ignored suite setup") }; @AfterClass fun cleanup() { fail("ignored suite cleanup") } }
            @Test fun test() { fail("ignored suite test") }
        }
        object Singleton {
            var starts: Int = 0
            var bodies: Int = 0
            @BeforeClass private fun setup() { starts += 1; println("object.before") }
            @Test fun a() { assertEquals(1, starts); bodies += 1 }
            @Test fun b() { assertEquals(1, starts); bodies += 1 }
            @AfterClass private fun cleanup() { assertEquals(2, bodies); println("object.after") }
        }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        SKIP lifecycle.AllIgnored.test
        suite.before
        base.before
        derived.before
        a
        derived.after
        base.after
        PASS lifecycle.Derived.a
        base.before
        derived.before
        b
        derived.after
        base.after
        PASS lifecycle.Derived.b
        SKIP lifecycle.Derived.ignored
        suite.after
        object.before
        PASS lifecycle.Singleton.a
        PASS lifecycle.Singleton.b
        object.after
        SKIP lifecycle.Skipped.test
        Tests: 4 passed, 0 failed, 3 skipped

        """)
    }

    @Test(arguments: [false, true])
    func groupsFileSuitesAndImportsDefaultPackageClassHooks(fromSource: Bool) throws {
        let result = try compileAndRun([("a.kt", """
        import kotlin.test.*
        var startsA: Int = 0
        @BeforeClass private fun setupA() { startsA += 1; println("a.before") }
        @AfterClass private fun cleanupA() { assertEquals(1, startsA); println("a.after") }
        @BeforeTest private fun beforeA() { assertEquals(1, startsA) }
        @Test private fun a() { println("a.a") }
        @Test private fun z() { println("a.z") }
        """), ("b.kt", """
        import kotlin.test.*
        var startsB: Int = 0
        @BeforeClass private fun setupB() { startsB += 1; println("b.before") }
        @AfterClass private fun cleanupB() { assertEquals(1, startsB); println("b.after") }
        @Test private fun a() { assertEquals(1, startsB); println("b.a") }
        @Test private fun m() { assertEquals(1, startsB); println("b.m") }
        """), ("ignored.kt", """
        import kotlin.test.*
        @BeforeClass fun setup() { fail("ignored file setup") }
        @AfterClass fun cleanup() { fail("ignored file cleanup") }
        @Test @Ignore fun ignored() { fail("ignored file test") }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        a.before
        a.a
        PASS a [a.kt]
        a.z
        PASS z [a.kt]
        a.after
        b.before
        b.a
        PASS a [b.kt]
        b.m
        PASS m [b.kt]
        b.after
        SKIP ignored [ignored.kt]
        Tests: 4 passed, 0 failed, 1 skipped

        """)
    }

    @Test(arguments: [false, true])
    func inheritsObjectHooksAndKeepsNativeRegistrationOrder(fromSource: Bool) throws {
        let result = try compileAndRun([("objects.kt", """
        import kotlin.test.*
        open class Hooks {
            @BeforeClass open fun zSetup() { println("base.zSetup") }
            @BeforeClass open fun aSetup() { println("base.aSetup") }
            @AfterClass open fun zCleanup() { println("base.zCleanup") }
            @AfterClass open fun aCleanup() { println("base.aCleanup") }
            @BeforeClass private fun privateSetup() { fail("private hook is not inherited") }
        }
        interface Unrelated { @BeforeClass fun setup() { fail("interface hook is not inherited") } }
        object Suite: Hooks(), Unrelated {
            @BeforeClass private fun ownSetup() { println("own.setup") }
            override fun zSetup() { println("override.setup") }
            @AfterClass private fun ownCleanup() { println("own.cleanup") }
            @Test fun a() { println("a") }
            @Test fun b() { println("b") }
        }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        own.setup
        override.setup
        base.aSetup
        a
        PASS Suite.a
        b
        PASS Suite.b
        own.cleanup
        base.aCleanup
        base.zCleanup
        Tests: 2 passed, 0 failed, 0 skipped

        """)
    }

    @Test(arguments: [false, true])
    func resolvesInheritedIgnoreFromTheTestAnnotationOwner(fromSource: Bool) throws {
        let result = try compileAndRun([("ignore-owner.kt", """
        import kotlin.test.*
        abstract class IgnoredBase { @Test @Ignore open fun test() { fail("ignored base") } }
        abstract class ActiveBase { @Test open fun test() { println("inherited.test") } }
        open class Hooks {
            @BeforeClass open fun setup() { println("inherited.setup") }
            @AfterClass open fun cleanup() { println("inherited.cleanup") }
        }
        class AExplicitTest: IgnoredBase() {
            companion object: Hooks() {
                override fun setup() { println("override.setup") }
            }
            @Test override fun test() { println("explicit.test") }
        }
        class BIgnoreOnly: ActiveBase() {
            companion object {
                @BeforeClass fun setup() { println("ignore-only.setup") }
                @AfterClass fun cleanup() { println("ignore-only.cleanup") }
            }
            @Ignore override fun test() { println("ignore-only.test") }
        }
        class CInheritedIgnore: IgnoredBase() {
            companion object { @BeforeClass fun setup() { fail("inherited ignored setup") } }
            override fun test() { fail("inherited ignored test") }
        }
        class DExplicitIgnore: ActiveBase() {
            companion object { @BeforeClass fun setup() { fail("explicit ignored setup") } }
            @Test @Ignore override fun test() { fail("explicit ignored test") }
        }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        override.setup
        explicit.test
        PASS AExplicitTest.test
        inherited.cleanup
        ignore-only.setup
        ignore-only.test
        PASS BIgnoreOnly.test
        ignore-only.cleanup
        SKIP CInheritedIgnore.test
        SKIP DExplicitIgnore.test
        Tests: 2 passed, 0 failed, 2 skipped

        """)
    }

    @Test(arguments: [false, true])
    func preservesHiddenCompanionVisibilityWithoutConstructingExtraInstances(fromSource: Bool) throws {
        let result = try compileAndRun([("private-companions.kt", """
        import kotlin.test.*
        var instances: Int = 0
        class AUnnamed {
            init { instances += 1 }
            private companion object {
                @BeforeClass private fun setup() { assertEquals(0, instances); println("unnamed.before") }
                @AfterClass private fun cleanup() { assertEquals(1, instances); println("unnamed.after") }
            }
            @Test fun test() { println("unnamed.test") }
        }
        class BNamed {
            init { instances += 1 }
            private companion object Hidden {
                @BeforeClass private fun setup() { assertEquals(1, instances); println("named.before") }
                @AfterClass private fun cleanup() { assertEquals(2, instances); println("named.after") }
            }
            @Test fun test() { println("named.test") }
        }
        class CProtected {
            init { instances += 1 }
            protected companion object Hidden {
                @BeforeClass private fun setup() { assertEquals(2, instances); println("protected.before") }
                @AfterClass private fun cleanup() { assertEquals(3, instances); println("protected.after") }
            }
            @Test fun test() { println("protected.test") }
        }
        """)], fromSource: fromSource)
        #expect(result.exitCode == 0)
        #expect(result.stdout == """
        unnamed.before
        unnamed.test
        PASS AUnnamed.test
        unnamed.after
        named.before
        named.test
        PASS BNamed.test
        named.after
        protected.before
        protected.test
        PASS CProtected.test
        protected.after
        Tests: 3 passed, 0 failed, 0 skipped

        """)
    }

    @Test(arguments: [false, true], [false, true])
    func abortsOnClassHookFailures(fromSource: Bool, failBefore: Bool) throws {
        let before = failBefore ? "throw IllegalStateException(\"before class\")" : "println(\"before\")"
        let after = failBefore ? "println(\"NEVER AFTER\")" : "throw IllegalStateException(\"after class\")"
        let result = try compileAndRun([("abort.kt", """
        import kotlin.test.*
        object ASuite {
            @BeforeClass fun setup() { \(before) }
            @Test fun a() { println("test"); fail("body failure") }
            @AfterClass fun cleanup() { \(after) }
            @AfterClass fun laterCleanup() { println("NEVER LATER CLEANUP") }
        }
        object BSuite { @Test fun test() { println("NEVER LATER SUITE") } }
        """)], fromSource: fromSource)
        #expect(result.exitCode != 0)
        #expect(result.stdout == (failBefore ? "" : "before\ntest\nFAIL ASuite.a: body failure\n"))
        #expect(result.stderr.contains("KSWIFTK-LINK-0003"))
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
