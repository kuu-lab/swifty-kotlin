@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-1339: Unit literals and returned values share identity at erased boundaries.
    @Test(arguments: [false, true])
    func testUnitReturnSingleton(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/unit_return_singleton.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "UnitReturnSingleton",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            true
            true
            true
            true
            true
            true
            w
            true
            true
            true
            true
            true
            true
            true
            false
            false
            false
            false
            true
            boxed
            kotlin.Unit

            """)
        }
    }

    @Test(arguments: [false, true])
    func testOutputStreamBulkWritesPreserveBytes(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        import kotlinx.io.*
        import java.io.IOException

        fun main() {
            val buffer = Buffer()
            val out = buffer.asOutputStream()
            out.write(listOf(104, 105, 106, 0, 127, 128, 255, -1, 256))
            out.write(byteArrayOf(104, 105, 106, -128, -1))
            out.write(listOf<Int>())
            out.write(byteArrayOf())
            out.write(65)
            out.flush()
            println(buffer.size)
            while (buffer.size > 0) {
                println(buffer.readByte().toInt())
            }

            val raw: RawSink = Buffer()
            val closed = raw.buffered().asOutputStream()
            closed.close()
            try {
                closed.write(listOf(104, 105, 106))
                println("no-throw")
            } catch (e: IOException) {
                println(e.message)
            }
            try {
                closed.write(byteArrayOf(104, 105, 106))
                println("no-throw")
            } catch (e: IOException) {
                println(e.message)
            }
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "OutputStreamBulkWrites",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            15
            104
            105
            106
            0
            127
            -128
            -1
            -1
            0
            104
            105
            106
            -128
            -1
            65
            Underlying sink is closed.
            Underlying sink is closed.

            """)
        }
    }

    /// STDLIB-ARTIFACT-007: imported source-backed stdlib extension functions
    /// (e.g. `Duration.compareTo`) must be visible in the consumer's default-import
    /// scope so member-style calls resolve to the concrete extension instead of
    /// falling back to a broad short-name lookup that also sees `Comparable<T>.compareTo`
    /// and reports an ambiguous overload.
    @Test
    func testDurationCompareToSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val d1 = 1.seconds
            val d2 = 2.seconds
            println(d2.compareTo(d1))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "1\n")
        }
    }

    /// STDLIB-ARTIFACT-008: `java.io.Closeable` imported as a synthetic nominal
    /// anchor from a prebuilt stdlib artifact must retain its `kotlin.io.Closeable`
    /// supertype so that user implementations are recognised as `Closeable` and
    /// `.use {}` resolves and runs correctly.
    @Test
    func testCloseableUseSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import java.io.Closeable

        class MyResource(val name: String) : Closeable {
            override fun close() {
                println("$name closed")
            }
        }

        fun main() {
            val result = MyResource("r1").use {
                println("using r1")
                42
            }
            println("result=$result")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "using r1\nr1 closed\nresult=42\n")
        }
    }

    /// STDLIB-ARTIFACT-018: `Random.nextBytes(size: Int)` is an open method with
    /// multiple `nextBytes` overloads. The shared stdlib artifact's vtable slot
    /// layout must round-trip with enough type information to disambiguate
    /// overloads that have the same arity, so that `nextBytes(size)` dispatches to
    /// the correct `nextBytes(array)` implementation instead of an unmapped slot.
    @Test
    func testRandomNextBytesSizeSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.random.Random

        fun main() {
            println(Random(99).nextBytes(8).size)
            println(Random.nextBytes(8).size)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "8\n8\n")
        }
    }

    /// STDLIB-ARTIFACT-KOTLIN-VERSION: `kotlin.KotlinVersion` is bundled Kotlin
    /// source (`Stdlib/kotlin/KotlinVersion.kt`) whose only runtime dependency
    /// is the `__kk_kotlin_version_current` build-time constant. Through the
    /// shared artifact the class arrives as an imported (synthetic-flagged)
    /// symbol, which used to make `println(version)` fall back to
    /// `kk_any_to_string` and print `<object 0x...>` instead of dispatching the
    /// imported `toString()` override.
    @Test
    func testKotlinVersionThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val short = KotlinVersion(2, 1)
            val full = KotlinVersion(2, 1, 20)
            println(short)
            println(full)
            println(full.major.toString() + "/" + full.minor.toString() + "/" + full.patch.toString())
            println(KotlinVersion.MAX_COMPONENT_VALUE)
            println(short < full)
            println(full.compareTo(short) > 0)
            println(full.isAtLeast(2, 1))
            println(full.isAtLeast(2, 1, 21))
            println(full == KotlinVersion(2, 1, 20))
            println(KotlinVersion.CURRENT.isAtLeast(1, 0))
            println(KotlinVersion.CURRENT.toString())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                2.1.0
                2.1.20
                2/1/20
                255
                true
                true
                true
                false
                true
                true
                2.3.10

                """)
        }
    }

    /// KSP-707: symbols loaded from a precompiled stdlib library artifact carry
    /// both `.importedLibrary` and `.synthetic`, so `require`/`check`/`assert`'s
    /// `ContractNonNullEffect` (which powers `require(x != null)`-style smart-cast
    /// narrowing) must still be attached to those symbols and not skipped by a
    /// synthetic-only filter. Regression test for a bug introduced while
    /// relocating `patchSourceBackedPreconditionContractEffects` out of the
    /// now-deleted `HeaderHelpers+SyntheticPreconditionStubs.swift`: narrowing
    /// after `require`/`check` silently stopped resolving when compiling a
    /// consumer module against a shared `.kklib` artifact (the exact mode
    /// `Scripts/diff_kotlinc.sh` uses), while the inline-bundled-source
    /// compilation path kept working.
    @Test
    func testPreconditionSmartCastThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val x: String? = "hello"
            require(x != null)
            println(x.length)

            val y: String? = "world"
            check(y != null)
            println(y.length)

            val a: Any = "kotlin"
            require(a is String)
            println(a.length)

            val c: String? = "lazy"
            require(c != null) { "c must not be null" }
            println(c.length)

            val d: String? = "compound"
            val e: String? = "both"
            require(d != null && e != null)
            println(d.length + e.length)

            val f: String? = "asserted"
            assert(f != null)
            println(f.length)

            // KUU-1091: `contract { returns() implies (value != null) }` on
            // requireNotNull/checkNotNull must narrow the argument itself, not
            // just the call's return value.
            val g: String? = "notnull"
            requireNotNull(g)
            println(g.length)

            val h: String? = "checked"
            checkNotNull(h)
            println(h.length)

            val i: String? = "lazy2"
            requireNotNull(i) { "i must not be null" }
            println(i.length)

            val j: String? = "lazy3"
            checkNotNull(j) { "j must not be null" }
            println(j.length)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                5
                5
                6
                4
                12
                8
                7
                7
                5
                5

                """)
        }
    }
}
