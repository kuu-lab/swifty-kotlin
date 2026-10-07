@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibContainerTests {
    private static var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/demo.klib")
            .path
    }

    // MARK: - Packed archive

    @Test
    func readsPackedKlibFixture() throws {
        guard FileManager.default.fileExists(atPath: Self.fixturePath) else {
            return // fixture not present in this checkout
        }
        let container = try KlibContainer(path: Self.fixturePath)
        #expect(container.component == "default")

        let manifest = try container.manifest()
        #expect(manifest.uniqueName == "demo2")
        // Kotlin 2.4.20 fixture: newer than the 2.3.x support track.
        guard case .bestEffort = manifest.compatibility else {
            Issue.record("expected bestEffort, got \(manifest.compatibility)")
            return
        }

        let paths = container.entryPaths()
        #expect(paths.contains("ir/irDeclarations.knd"))
        #expect(paths.contains("ir/bodies.knb"))
        #expect(paths.contains("manifest"))
        #expect(container.contains("ir/types.knt"))
        #expect(!container.contains("ir/nonexistent.knt"))
    }

    @Test
    func readRejectsTraversal() throws {
        guard FileManager.default.fileExists(atPath: Self.fixturePath) else { return }
        let container = try KlibContainer(path: Self.fixturePath)
        #expect(throws: KlibFormatError.self) {
            _ = try container.read("../default/manifest")
        }
        #expect(throws: KlibFormatError.self) {
            _ = try container.read("/absolute/path")
        }
        #expect(throws: KlibFormatError.self) {
            _ = try container.read("no/such/entry")
        }
    }

    // MARK: - Unpacked directory

    @Test
    func readsUnpackedKlibDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let component = root.appendingPathComponent("default")
        try fm.createDirectory(
            at: component.appendingPathComponent("ir"),
            withIntermediateDirectories: true
        )
        defer { try? fm.removeItem(at: root) }

        let manifestText = "unique_name=unpacked\nabi_version=2.3.0\nir_signature_versions=1\n"
        try manifestText.write(
            to: component.appendingPathComponent("manifest"),
            atomically: true, encoding: .utf8
        )
        try "payload".write(
            to: component.appendingPathComponent("ir/files.knf"),
            atomically: true, encoding: .utf8
        )

        // A directory named *.klib is a valid unpacked container.
        let klibDir = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).klib")
        try fm.createDirectory(at: klibDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: klibDir) }
        try fm.copyItem(at: component, to: klibDir.appendingPathComponent("default"))

        let container = try KlibContainer(path: klibDir.path)
        #expect(container.component == "default")
        let manifest = try container.manifest()
        #expect(manifest.uniqueName == "unpacked")
        #expect(manifest.compatibility == .supported)
        #expect(container.entryPaths().contains("ir/files.knf"))
        #expect(String(decoding: try container.read("ir/files.knf"), as: UTF8.self) == "payload")
        #expect(container.contains("manifest"))
        #expect(throws: KlibFormatError.self) {
            _ = try container.read("../outside")
        }
    }

    @Test
    func rejectsContainerWithoutManifest() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).klib")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("default.txt"), atomically: true, encoding: .utf8)
        #expect(throws: KlibFormatError.self) {
            _ = try KlibContainer(path: root.path)
        }
    }

    // MARK: - Discovery + import pipeline wiring

    @Test
    func discoveryFindsKlibFilesAlongsideKklibDirs() throws {
        guard FileManager.default.fileExists(atPath: Self.fixturePath) else { return }
        let fm = FileManager.default
        let searchDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: searchDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: searchDir) }

        // Packed .klib file inside the search directory.
        try fm.copyItem(
            atPath: Self.fixturePath,
            toPath: searchDir.appendingPathComponent("demo.klib").path
        )
        // Empty .kklib directory bundle.
        try fm.createDirectory(
            at: searchDir.appendingPathComponent("empty.kklib"),
            withIntermediateDirectories: true
        )
        // A non-library entry is ignored.
        try "noise".write(
            to: searchDir.appendingPathComponent("noise.txt"),
            atomically: true, encoding: .utf8
        )

        let found = DataFlowSemaPhase().discoverLibraryDirectories(searchPaths: [searchDir.path])
        #expect(found.contains { $0.hasSuffix("demo.klib") })
        #expect(found.contains { $0.hasSuffix("empty.kklib") })
        #expect(!found.contains { $0.hasSuffix("noise.txt") })

        // A search path may also point directly at the archive file.
        let direct = DataFlowSemaPhase().discoverLibraryDirectories(
            searchPaths: [searchDir.appendingPathComponent("demo.klib").path]
        )
        #expect(direct.count == 1)
        #expect(direct[0].hasSuffix("demo.klib"))
    }

    @Test
    func importLoopLoadsKlibModule() throws {
        guard FileManager.default.fileExists(atPath: Self.fixturePath) else { return }
        let fm = FileManager.default
        let searchDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: searchDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: searchDir) }
        try fm.copyItem(
            atPath: Self.fixturePath,
            toPath: searchDir.appendingPathComponent("demo.klib").path
        )

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "KlibApp",
                emit: .kirDump,
                searchPaths: [searchDir.path]
            )
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: SymbolTable(),
                types: TypeSystem(),
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: ImportedInlineFunctionStore()
            )

            #expect(work.klibModules.count == 1)
            #expect(work.klibModules.first?.uniqueName == "demo2")
            #expect(!diagnostics.hasError,
                    "unexpected errors: \(diagnostics.diagnostics.map(\.code))")
            let codes = Set(diagnostics.diagnostics.map(\.code))
            #expect(codes.contains("KSWIFTK-LIB-0027")) // bestEffort: abi 2.4
            // Declaration materialization is implemented; no import warnings.
            #expect(!codes.contains("KSWIFTK-LIB-0028"))
        }
    }

    @Test
    func importLoopRejectsUnrelatedFile() throws {
        let fm = FileManager.default
        let bogus = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).klib")
        try "definitely not a zip".write(to: bogus, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: bogus) }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BogusKlibApp",
                emit: .kirDump,
                searchPaths: [bogus.path]
            )
            let diagnostics = DiagnosticEngine()
            let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: SymbolTable(),
                types: TypeSystem(),
                diagnostics: diagnostics,
                interner: StringInterner(),
                importedInlineFunctions: ImportedInlineFunctionStore()
            )
            #expect(work.klibModules.isEmpty)
            #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0025" })
        }
    }
}
