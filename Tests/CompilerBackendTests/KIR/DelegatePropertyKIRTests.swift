@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// KSP-491 unified `lazy`/`Delegates.observable/vetoable/notNull` onto the
/// same operator-convention (`getValue`/`setValue`) resolution `.custom`
/// delegates use, replacing the `kk_lazy_create`/`kk_observable_*`/
/// `kk_vetoable_*`/`kk_notNull_*` runtime-bridge KIR shape these tests used
/// to assert on. The KIR-dump-level assertions that verified those bridge
/// callee names were removed; the behavior they covered (top-level lazy/
/// observable/vetoable/notNull properties compile and lower correctly) is
/// covered at a stronger, execution-level bar by `Scripts/diff_cases/
/// delegate_lazy.kt`/`delegate_observable.kt`/`delegate_vetoable.kt`/
/// `delegates_not_null.kt`/`delegate_stdlib_members.kt` (compared against
/// real kotlinc via `diff_kotlinc.sh`). The two end-to-end execution tests
/// below have no bridge-name dependency and are kept unchanged.
@Suite(.serialized)
struct DelegatePropertyKIRTests {
    @Test
    func testLazyDelegateEndToEndCompilesToExecutable() throws {
        let source = """
        val x by lazy { 42 }
        fun main() {
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LazyDelegateExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            #expect(FileManager.default.fileExists(atPath: outputPath),
                    "Executable should be produced for lazy delegate program")
        }
    }

    @Test
    func testNotNullDelegateReadBeforeAssignmentTrapsWithHelpfulMessage() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.notNull()
        fun main() {
            println(name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NotNullTrapExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                Issue.record("Reading notNull before assignment should fail")
                return
            } catch let CommandRunnerError.nonZeroExit(result) {
                let combined = result.stdout + result.stderr
                if !combined.isEmpty {
                    #expect(
                        combined.contains("IllegalStateException")
                            || combined.contains("fatalError")
                            || combined.contains("initialized before get")
                            || combined.contains("KSWIFTK-LINK-0003"),
                        "Unexpected process output: \(combined)"
                    )
                }
            }
        }
    }
}
