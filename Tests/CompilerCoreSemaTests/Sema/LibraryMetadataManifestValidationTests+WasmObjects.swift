#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LibraryMetadataManifestValidationTests {
    @Test
    func wasmStdlibManifestAllowsEmptyObjectsList() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("wasm-stdlib-manifest-\(UUID().uuidString).kklib", isDirectory: true)
        defer { try? fm.removeItem(at: directory) }
        try fm.createDirectory(at: directory.appendingPathComponent("inline-kir"), withIntermediateDirectories: true)
        for path in ["metadata.bin", "bundled-members.bin"] {
            try Data().write(to: directory.appendingPathComponent(path))
        }
        let target = TargetTriple.wasmWASI
        let manifest: [String: Any] = [
            "formatVersion": 2,
            "moduleName": "KSwiftKStdlib",
            "libraryKind": "stdlib",
            "stdlibManifestHash": BundledStdlib.manifestHash(),
            "kotlinLanguageVersion": "2.4.20",
            "target": "\(target.arch)-\(target.vendor)-\(target.os)",
            "compilerVersion": "0.1.0",
            "metadata": "metadata.bin",
            "inlineKIRDir": "inline-kir",
            "objects": [],
            "bundledMemberIndex": "bundled-members.bin",
            "precomputedSyntheticStubs": true,
            "precomputedReflectionRecords": true,
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: directory.appendingPathComponent("manifest.json"))

        let diagnostics = DiagnosticEngine()
        let info = DataFlowSemaPhase().resolveLibraryManifestInfo(
            libraryDir: directory.path,
            currentTarget: target,
            diagnostics: diagnostics,
            isStdlibArtifact: true
        )
        #expect(info.isValid)
        #expect(info.hasPrecomputedReflectionRecords)
        #expect(!diagnostics.hasError)
    }
}
#endif
