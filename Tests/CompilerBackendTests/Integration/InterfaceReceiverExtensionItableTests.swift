#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// KUU-545: declaring a bundled `internal external fun <interface>.member()`
/// extension must not corrupt itable dispatch for that interface. The KSP-443
/// lookup alias registered under the receiver nominal used to be counted as a
/// real interface method, inflating `CharSequence`'s `vtableSize` and moving
/// the `length` property getter off itable slot 2 — the fixed slot that
/// `runtimeRegisterCharSequenceItable` registers for String objects — so any
/// `CharSequence`-typed `length`/`get` call panicked with
/// `KSWIFTK-RUNTIME-0001` even when the new function was never called.
///
/// The trigger must be a bundled-source declaration (`external fun` and
/// `@KsSymbolName` are bundled-only) compiled alongside the bundled stdlib
/// sources, so this test injects an extra bundled file and compiles the stdlib
/// from source (`allowDefaultStdlibLibrary: false`).
@Suite
struct InterfaceReceiverExtensionItableTests {
    private let probeSource = """
    package kotlin.text

    import kotlin.internal.KsSymbolName

    @KsSymbolName("__kk_kuu545_iface_probe")
    internal external fun CharSequence.__kk_kuu545_iface_probe(): Int
    """

    private let callerSource = """
    fun main() {
        var sum = 0
        for (c in "abc") { sum += c.code }
        println(sum)
    }
    """

    @Test
    func testInterfaceReceiverExternalExtensionDoesNotCorruptItableDispatch() throws {
        let bundledPath = "__bundled_kuu545_probe.kt"
        try withTemporaryFile(contents: callerSource) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let sourceManager = SourceManager()
            _ = sourceManager.addFile(
                path: bundledPath,
                contents: Data(probeSource.utf8),
                origin: .bundledStdlib
            )

            let options = CompilerOptions(
                moduleName: "Kuu545Itable",
                inputs: [userPath],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple(),
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: sourceManager,
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToLowering(ctx)
            try assertNoDiagnosticErrors(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "294\n")
        }
    }
}
#endif
