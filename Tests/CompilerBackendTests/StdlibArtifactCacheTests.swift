@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct StdlibArtifactCacheTests {
    @Test
    func packagedCandidatesCoverDeveloperAndInstalledLayouts() {
        let candidates = StdlibArtifactCache.packagedArtifactCandidates(
            executablePath: "/opt/kswiftk/bin/kswiftc"
        )

        #expect(candidates.contains("/opt/kswiftk/bin/KSwiftKStdlib.kklib"))
        #expect(candidates.contains("/opt/kswiftk/bin/stdlib/KSwiftKStdlib.kklib"))
        #expect(candidates.contains("/opt/kswiftk/bin/KSwiftK_CompilerCore.resources/KSwiftKStdlib.kklib"))
        #expect(candidates.contains(
            "/opt/kswiftk/bin/KSwiftK_CompilerCore.bundle/Contents/Resources/KSwiftKStdlib.kklib"
        ))
        #expect(candidates.contains("/opt/kswiftk/lib/kswiftk/stdlib/KSwiftKStdlib.kklib"))
        #expect(Set(candidates).count == candidates.count)
    }

    @Test
    func sharedBuilderProducesAValidatedStdlibManifest() throws {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-stdlib-cache-test-\(UUID().uuidString)")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: outputBase + ".kklib")
        }

        let artifactPath = try StdlibArtifactBuilder.build(
            outputBase: outputBase,
            target: TargetTriple.hostDefault()
        )
        let manifestPath = URL(fileURLWithPath: artifactPath)
            .appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestPath)
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(manifest["formatVersion"] as? Int == 1)
        #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
        #expect(manifest["libraryKind"] as? String == "stdlib")
        #expect(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
        #expect(manifest["target"] as? String == "\(TargetTriple.hostDefault().arch)-\(TargetTriple.hostDefault().vendor)-\(TargetTriple.hostDefault().os)")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
    }
}
