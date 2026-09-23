@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct LinkPhaseIntegrationTests {
    @Test
    func testLinkPhaseAutoLinksKotlinLibraryObjectForCrossModuleCall() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            // Observe the cross-module result on stdout: `main`'s own value is
            // never the process status (see
            // `testEntryWrapperDiscardsNonUnitMainResult`).
            let appSource = """
            import extdemo.plus
            fun main() {
                println(plus(41))
            }
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "CrossModuleApp",
                    emit: .executable,
                    outputPath: outputPath,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)
                try CodegenPhase().run(appCtx)
                assertLinkSucceeds(appCtx)

                #expect(FileManager.default.fileExists(atPath: outputPath))
                let result = try CommandRunner.run(executable: outputPath, arguments: [])
                #expect(result.stdout.trimmingCharacters(in: .newlines) == "42")
            }
        }
    }

    @Test
    func testLinkPhaseReportsMissingMainAndCanLinkExecutable() throws {
        try withTemporaryFile(contents: "fun notMain() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoMain", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            #expect(throws: (any Error).self) {
                try LinkPhase().run(ctx)
            }
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0002" })
        }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "HasMain",
                inputs: [path],
                outputPath: out,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            #expect(FileManager.default.fileExists(atPath: out))
        }
    }

    @Test
    func testLinkPhaseWrapperReportsTopLevelThrownException() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(1)
            return arr[2]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "TopLevelThrow", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            #expect(FileManager.default.fileExists(atPath: out))

            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: out, arguments: [])
                Issue.record("Expected executable to fail on unhandled top-level exception.")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                result = failed
            } catch {
                Issue.record("Unexpected error: \(error)")
                return
            }

            #expect(result.exitCode == 1)
            #expect(result.stderr.contains("KSWIFTK-LINK-0003"))
            #expect(result.stderr.contains("KSwiftK panic"))
        }
    }

    /// `main`'s own value must never reach the process status.
    ///
    /// kotlinc does not recognise a `main` whose return type is not `Unit` as
    /// an entry point at all, so it emits a jar without a `Main-Class`.
    /// KSwiftK keeps accepting such a `main` — rejecting it is not an option
    /// while `runBlocking`/`coroutineScope`/`Deferred.await` are modelled as
    /// returning `Any`, which makes every `fun main() = runBlocking { ... }`
    /// non-`Unit` regardless of its body — but the value is discarded, which
    /// is what a Kotlin program observes: a non-zero status comes only from
    /// `exitProcess` or an unhandled exception. The entry wrapper used to
    /// truncate the entry function's `i64` result into `main`'s `i32` ABI, so
    /// `fun main(): Int = 42` exited 42, and a boxed result leaked the low
    /// bits of a heap pointer — a different status on each run of one binary.
    @Test
    func testEntryWrapperDiscardsNonUnitMainResult() throws {
        let cases: [(module: String, source: String, expectedStdout: String)] = [
            (
                "IntMainExitStatus",
                """
                fun main(): Int = 42
                """,
                ""
            ),
            (
                // A boxed result is the shape whose leaked status varied
                // run-to-run, so this case is checked more than once below.
                "BoxedMainExitStatus",
                """
                fun main(): Any {
                    println("ran")
                    return "boxed"
                }
                """,
                "ran\n"
            ),
        ]

        for testCase in cases {
            try withTemporaryFile(contents: testCase.source) { path in
                let out = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: out) }
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: testCase.module,
                    emit: .executable,
                    outputPath: out
                )
                try runToKIR(ctx)
                try LoweringPhase().run(ctx)
                try CodegenPhase().run(ctx)
                assertLinkSucceeds(ctx)

                for attempt in 1...3 {
                    do {
                        let result = try CommandRunner.run(executable: out, arguments: [])
                        #expect(result.exitCode == 0)
                        #expect(result.stdout == testCase.expectedStdout)
                    } catch let CommandRunnerError.nonZeroExit(failed) {
                        Issue.record(
                            """
                            \(testCase.module) run \(attempt) exited \(failed.exitCode); \
                            expected 0 because main's value is not the exit status.
                            """
                        )
                    }
                }
            }
        }
    }

    /// The coroutine shape from the original report: `coroutineScope` and
    /// `Deferred.await` are modelled as returning `Any`, so a `try` whose body
    /// is a `coroutineScope { ... }` widens `main` to `Any` and used to leak a
    /// boxed pointer into the exit status.
    @Test
    func testEntryWrapperDiscardsCoroutineMainResult() throws {
        let source = """
        import kotlinx.coroutines.*

        suspend fun boom(): Int {
            throw RuntimeException("boom")
        }

        fun main() = runBlocking {
            try {
                coroutineScope {
                    val a = async { 10 }
                    val b = async { boom() }
                    a.await()
                    b.await()
                }
            } catch (e: Throwable) {
                println(e.message)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: out) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CoroutineMainExitStatus",
                emit: .executable,
                outputPath: out
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            for attempt in 1...3 {
                do {
                    let result = try CommandRunner.run(executable: out, arguments: [])
                    #expect(result.exitCode == 0)
                    #expect(result.stdout.trimmingCharacters(in: .newlines) == "boom")
                } catch let CommandRunnerError.nonZeroExit(failed) {
                    Issue.record(
                        """
                        Coroutine main run \(attempt) exited \(failed.exitCode); \
                        expected 0 because main's value is not the exit status.
                        """
                    )
                }
            }
        }
    }

    @Test
    func testLinkPhaseAutoLinksKklibManifestObjectsAndDeduplicates() throws {
        let fm = FileManager.default
        let workspaceDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspaceDir) }

        let libraryDir = workspaceDir.appendingPathComponent("NativePlus.kklib")
        let objectsDir = libraryDir.appendingPathComponent("objects")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)

        let cSource = """
        #include <stdint.h>
        intptr_t plus(intptr_t value, intptr_t* outThrown) {
            (void)outThrown;
            return value + 1;
        }
        """
        let cSourceURL = workspaceDir.appendingPathComponent("native_plus.c")
        try cSource.write(to: cSourceURL, atomically: true, encoding: .utf8)

        let objectURL = objectsDir.appendingPathComponent("native_plus.o")
        let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
        _ = try CommandRunner.run(
            executable: clangPath,
            arguments: ["-c", cSourceURL.path, "-o", objectURL.path]
        )

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NativePlus",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "arm64-apple-macosx",
          "objects": ["objects/native_plus.o", "objects/native_plus.o"],
          "metadata": "metadata.bin"
        }
        """
        try manifest.write(
            to: libraryDir.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try "symbols=0\n".write(
            to: libraryDir.appendingPathComponent("metadata.bin"),
            atomically: true,
            encoding: .utf8
        )

        // `plus` comes from the hand-written object in the manifest and carries no
        // Kotlin type information (`metadata.bin` declares `symbols=0`), so its
        // result cannot be printed — `println` would render the raw value as
        // "null". Route it through `exitProcess`, the only way a Kotlin program
        // picks a process status: `main`'s own value is discarded by the entry
        // wrapper (see `testEntryWrapperDiscardsNonUnitMainResult`).
        let appSource = """
        import kotlin.system.exitProcess
        fun main() {
            exitProcess(plus(41))
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = workspaceDir.appendingPathComponent("AppExecutable").path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "App",
                emit: .executable,
                outputPath: outputPath,
                searchPaths: [libraryDir.path, workspaceDir.path]
            )
            try runToKIR(appCtx)
            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            #expect(fm.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                Issue.record("Expected exitProcess(plus(41)) to exit with 42")
            } catch let CommandRunnerError.nonZeroExit(failed) {
                #expect(failed.exitCode == 42)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func testLinkPhaseSkipsForObjectEmitMode() throws {
        let objectCtx = makeCompilationContext(inputs: [], moduleName: "SkipLink", emit: .object)
        try LinkPhase().run(objectCtx)
    }

    @Test
    func testLinkPhaseFailsWhenObjectIsMissingForExecutable() throws {
        let missingObjectCtx = makeCompilationContext(inputs: [], moduleName: "MissingObj", emit: .executable)
        #expect(throws: (any Error).self) {
            try LinkPhase().run(missingObjectCtx)
        }
    }

    @Test
    func testLinkPhaseFailsWhenKIRModuleIsMissing() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let noKirCtx = makeCompilationContext(inputs: [], moduleName: "NoKir", emit: .executable)
        noKirCtx.generatedObjectPath = tempObjectURL.path
        #expect(throws: (any Error).self) {
            try LinkPhase().run(noKirCtx)
        }
    }

    @Test
    func testLinkPhasePassesDebugFlagToExecutableLink() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugLink",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                debugInfo: true
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath))
        }
    }

    @Test
    func testLinkerDriverArgsDisablePieForLinuxTargets() {
        let linuxTarget = TargetTriple(arch: "x86_64", vendor: "unknown", os: "linux-gnu", osVersion: nil)
        let args = LinkPhase().linkerDriverArgs(for: linuxTarget)

        #expect(Array(args.prefix(2)) == ["-target", "x86_64-unknown-linux-gnu"])
        #expect(Array(args.suffix(5)) == [
            "-Xlinker", "--gc-sections",
            "-Xlinker", "-no-pie",
            "-parse-as-library",
        ])
    }

    @Test
    func testLinkerDriverArgsEnableDeadStripForAppleTargets() {
        let macTarget = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let args = LinkPhase().linkerDriverArgs(for: macTarget)

        #expect(Array(args.suffix(2)) == ["-Xlinker", "-dead_strip"])
        #expect(!args.contains("--gc-sections"))
    }

    @Test
    func testLinuxAutolinkStubIsRewrittenWhenCorrupted() throws {
        // Use a test-only triple so the stub path is isolated from any real target, even though
        // each LinkPhase now writes its autolink stub to a unique per-instance directory.
        let linuxTarget = TargetTriple(arch: "x86_64", vendor: "kswiftkstubtest", os: "linux-gnu", osVersion: nil)
        let linkPhase = LinkPhase()

        let stubPath = try #require(try linkPhase.emitSwiftAutolinkStubIfNeeded(target: linuxTarget))
        try "corrupted".write(toFile: stubPath, atomically: true, encoding: .utf8)

        let repairedPath = try #require(try linkPhase.emitSwiftAutolinkStubIfNeeded(target: linuxTarget))
        #expect(repairedPath == stubPath)

        let contents = try String(contentsOfFile: repairedPath, encoding: .utf8)
        #expect(contents != "corrupted")
        #expect(contents.contains("_kswiftkRuntimeAutolinkAnchor"))
        #expect(contents.contains("NSLock()"))
        #expect(contents.contains("DispatchQueue.global"))
        #expect(contents.contains("DispatchSemaphore(value: 0)"))
    }

    @Test
    func testExecutableEmissionWithOutputExtensionUsesSeparateObjectPath() throws {
        let source = """
        fun main() {
            println("%b %B".format(true, false))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("out")
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ExtensionOutput",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            #expect(ctx.generatedObjectPath == outputPath + ".o")
            #expect(ctx.generatedObjectPath != outputPath)

            assertLinkSucceeds(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true FALSE")
        }
    }

    @Test
    func testExecutableEmissionWithObjectOutputPathUsesSeparateIntermediateObjectPath() throws {
        let source = """
        fun main() {
            println(42)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("o")
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ObjectSuffixOutput",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            #expect(
                ctx.generatedObjectPath ==
                URL(fileURLWithPath: outputPath)
                    .deletingPathExtension()
                    .appendingPathExtension("executable")
                    .appendingPathExtension("o")
                    .path
            )
            #expect(ctx.generatedObjectPath != outputPath)

            assertLinkSucceeds(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
        }
    }

    @Test
    func testExecutableStringFormatHandlesBoxedScalarsInRuntimeObjects() throws {
        let source = """
        fun main() {
            val big: Any? = 9223372036854775807L
            val fp: Any? = 2.5
            val ch: Any? = 'A'
            val flag: Any? = true
            println("%d %x %s %s %s".format(big, big, fp, ch, flag))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "StringFormatBoxes",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(
                result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ==
                "9223372036854775807 7fffffffffffffff 2.5 A true"
            )
        }
    }

    @Test
    func testExecutableStringFormatSupportsScientificNotation() throws {
        let source = """
        fun main() {
            println("%.2e".format(1234.5))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "StringFormatScientific",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1.23e+03")
        }
    }

    @Test
    func testLinkPhaseReportsDiagnosticForUnsupportedTargetArchitecture() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let interner = StringInterner()
        let arena = KIRArena()
        let mainSym = SymbolID(rawValue: 99)
        let mainDecl = arena.appendDecl(.function(KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDecl])], arena: arena)

        let badTargetOptions = CompilerOptions(
            moduleName: "BadTarget",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .executable,
            target: TargetTriple(arch: "definitely-bad-arch", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let badTargetCtx = CompilationContext(
            options: badTargetOptions,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        badTargetCtx.generatedObjectPath = tempObjectURL.path
        badTargetCtx.kir = module

        #expect(throws: (any Error).self) {
            try LinkPhase().run(badTargetCtx)
        }
        #expect(badTargetCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0001" })
    }

    #if os(macOS)
        @Test
        func testRuntimeObjectPathsBuildForAlternateAppleArchitecture() throws {
            let hostTarget = TargetTriple.hostDefault()
            let alternateArch = hostTarget.arch == "arm64" ? "x86_64" : "arm64"
            let alternateTarget = TargetTriple(
                arch: alternateArch,
                vendor: hostTarget.vendor,
                os: hostTarget.os,
                osVersion: hostTarget.osVersion
            )

            let runtimeObjects = try CodegenRuntimeSupport.runtimeObjectPaths(target: alternateTarget)

            #expect(!runtimeObjects.isEmpty)
            #expect(runtimeObjects.allSatisfy { FileManager.default.fileExists(atPath: $0) })
            #expect(runtimeObjects.allSatisfy { $0.contains("\(alternateArch)-apple-macosx") })
        }
    #endif
}

private func assertLinkSucceeds(_ ctx: CompilationContext) {
    do {
        try LinkPhase().run(ctx)
    } catch {
        let diagnostics = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: "\n")
        let diagnosticSummary = diagnostics.isEmpty ? "No diagnostics were recorded." : diagnostics
        Issue.record(
            """
            LinkPhase failed with error: \(error)
            Diagnostics:
            \(diagnosticSummary)
            """
        )
    }
}
