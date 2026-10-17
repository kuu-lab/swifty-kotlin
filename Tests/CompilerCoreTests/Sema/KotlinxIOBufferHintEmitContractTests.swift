@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KotlinxIOBufferHintEmitContractTests {
    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        if let artifact {
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                URL(fileURLWithPath: artifact).appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let result = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = result.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(result.options.includeStdlib == !library && result.options.stdlibLibraryPath == artifact)
        return result
    }

    @Test(arguments: [false, true])
    func bufferHintEmitRequiresInternalOptInForSourceAndImportedLibrary(library: Bool) throws {
        let positive = """
        @file:OptIn(kotlinx.io.InternalIoApi::class)
        import kotlinx.io.Buffer

        fun useBufferHintEmit(buffer: Buffer) {
            buffer.hintEmit()
        }
        """
        let accepted = try context(positive, library: library)
        try runSema(accepted)
        #expect(!accepted.diagnostics.diagnostics.contains { $0.severity == .error },
            "Explicit InternalIoApi opt-in must allow Buffer.hintEmit(): \(accepted.diagnostics.diagnostics)")

        let negative = """
        import kotlinx.io.Buffer

        fun useBufferHintEmit(buffer: Buffer) {
            buffer.hintEmit()
        }
        """
        let rejected = try context(negative, library: library)
        try runSema(rejected)
        let diagnostics = rejected.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(diagnostics.count == 1, "Exactly the direct Buffer.hintEmit() call must require opt-in: \(diagnostics)")
        #expect(diagnostics.first?.severity == .error)
        #expect(diagnostics.first?.message.contains("kotlinx.io.InternalIoApi") == true)
    }
}
