@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibManifestTests {
    // MARK: - Java properties parsing

    @Test
    func propertiesParseBasicForms() throws {
        let pairs = try JavaProperties.parse("""
        # comment line
        ! bang comment
          unique_name = demo
        abi_version=2.4.0
        compiler_version:2.4.20
        depends=stdlib kotlinx\\ serialization
        """)
        let dict = Dictionary(pairs, uniquingKeysWith: { _, last in last })
        #expect(dict["unique_name"] == "demo")
        #expect(dict["abi_version"] == "2.4.0")
        #expect(dict["compiler_version"] == "2.4.20")
        #expect(dict["depends"] == "stdlib kotlinx\\ serialization".replacingOccurrences(of: "\\", with: ""))
    }

    @Test
    func propertiesParseContinuationAndEscapes() throws {
        let pairs = try JavaProperties.parse("key=one\\\n  two\nesc=a\\tb\\tc=\\u0041")
        let dict = Dictionary(pairs, uniquingKeysWith: { _, last in last })
        #expect(dict["key"] == "onetwo")
        #expect(dict["esc"] == "a\tb\tc=A")
    }

    @Test
    func propertiesDuplicateKeysKeepLast() throws {
        let pairs = try JavaProperties.parse("a=1\na=2\n")
        let dict = Dictionary(pairs, uniquingKeysWith: { _, last in last })
        #expect(dict["a"] == "2")
    }

    // MARK: - KlibManifest

    @Test
    func manifestRequiresUniqueName() {
        #expect(throws: KlibFormatError.missingManifestKey("unique_name")) {
            _ = try KlibManifest(contents: "abi_version=2.3.0\n")
        }
    }

    @Test
    func manifestParsesVersionsAndDepends() throws {
        let manifest = try KlibManifest(contents: """
        unique_name=demo
        abi_version=2.3.0
        compiler_version=2.3.10
        metadata_version=2.3.0
        ir_signature_versions=1,2
        depends=kotlin kotlinx.coroutines
        library_version=1.0
        builtins_platform=NATIVE
        """)
        #expect(manifest.uniqueName == "demo")
        #expect(manifest.abiVersion == KlibManifest.Version("2.3.0"))
        #expect(manifest.compilerVersion == KlibManifest.Version("2.3.10"))
        #expect(manifest.metadataVersion == KlibManifest.Version("2.3.0"))
        #expect(manifest.irSignatureVersions == [1, 2])
        #expect(manifest.depends == ["kotlin", "kotlinx.coroutines"])
        #expect(manifest.libraryVersion == "1.0")
        #expect(manifest.builtinsPlatform == "NATIVE")
        #expect(manifest.compatibility == .supported)
    }

    @Test
    func manifestCompilerVersionToleratesDevSuffix() throws {
        let manifest = try KlibManifest(contents: "unique_name=d\ncompiler_version=2.4.20-dev-7885\n")
        #expect(manifest.compilerVersion == KlibManifest.Version("2.4.20"))
    }

    // MARK: - Compatibility gate

    @Test
    func compatibilitySupportedAbi() throws {
        let manifest = try KlibManifest(contents: "unique_name=d\nabi_version=2.3.0\nir_signature_versions=1\n")
        #expect(manifest.compatibility == .supported)
    }

    @Test
    func compatibilityNewerAbiIsBestEffort() throws {
        let manifest = try KlibManifest(contents: "unique_name=d\nabi_version=2.4.0\nir_signature_versions=1\n")
        guard case .bestEffort = manifest.compatibility else {
            Issue.record("expected bestEffort, got \(manifest.compatibility)")
            return
        }
    }

    @Test
    func compatibilityRejectsForeignAbi() throws {
        for abi in ["1.201.0", "2.5.0", "3.0.0"] {
            let manifest = try KlibManifest(contents: "unique_name=d\nabi_version=\(abi)\nir_signature_versions=1\n")
            guard case .unsupported = manifest.compatibility else {
                Issue.record("expected unsupported for abi \(abi), got \(manifest.compatibility)")
                continue
            }
        }
    }

    @Test
    func compatibilityRejectsMissingAbi() throws {
        let manifest = try KlibManifest(contents: "unique_name=d\n")
        guard case .unsupported(let reason) = manifest.compatibility else {
            Issue.record("expected unsupported, got \(manifest.compatibility)")
            return
        }
        #expect(reason.contains("abi_version"))
    }

    @Test
    func compatibilityRejectsMissingV1Signature() throws {
        let manifest = try KlibManifest(contents: "unique_name=d\nabi_version=2.3.0\nir_signature_versions=2\n")
        guard case .unsupported = manifest.compatibility else {
            Issue.record("expected unsupported, got \(manifest.compatibility)")
            return
        }
    }
}
