@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibDependencyTests {
    /// Creates an unpacked `.klib` directory containing only a manifest —
    /// enough for `loadKlibModule`/`resolveKlibDependencies`, which do not
    /// touch the IR chunks.
    private static func makeUnpackedKlib(
        in directory: URL,
        name: String,
        depends: [String] = []
    ) throws -> URL {
        let klib = directory.appendingPathComponent("\(name).klib")
            .appendingPathComponent("default")
        try FileManager.default.createDirectory(at: klib, withIntermediateDirectories: true)
        var manifest = """
        unique_name=\(name)
        abi_version=2.3.0
        ir_signature_versions=1

        """
        if !depends.isEmpty {
            manifest += "depends=\(depends.joined(separator: " "))\n"
        }
        try manifest.write(
            to: klib.appendingPathComponent("manifest"),
            atomically: true,
            encoding: .utf8
        )
        return klib.deletingLastPathComponent()
    }

    @Test
    func ordersDependenciesBeforeDependents() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Declared in reverse order on purpose — `app` depends on `lib`.
        let app = try Self.makeUnpackedKlib(in: dir, name: "app", depends: ["lib"])
        let lib = try Self.makeUnpackedKlib(in: dir, name: "lib")

        let phase = DataFlowSemaPhase()
        let diagnostics = DiagnosticEngine()
        let appModule = phase.loadKlibModule(path: app.path, diagnostics: diagnostics)
        let libModule = phase.loadKlibModule(path: lib.path, diagnostics: diagnostics)
        let ordered = phase.resolveKlibDependencies(
            [appModule, libModule].compactMap { $0 },
            stdlibPresent: true,
            diagnostics: diagnostics
        )
        #expect(ordered.map(\.uniqueName) == ["lib", "app"])
        #expect(!diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0030" })
    }

    @Test
    func warnsOnMissingDependency() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = try Self.makeUnpackedKlib(in: dir, name: "app", depends: ["missinglib"])

        let phase = DataFlowSemaPhase()
        let diagnostics = DiagnosticEngine()
        let appModule = try #require(phase.loadKlibModule(path: app.path, diagnostics: diagnostics))
        let ordered = phase.resolveKlibDependencies(
            [appModule],
            stdlibPresent: true,
            diagnostics: diagnostics
        )
        #expect(ordered.map(\.uniqueName) == ["app"])
        let missing = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0030" }
        #expect(missing.count == 1)
        #expect(missing.first?.message.contains("missinglib") == true)
    }

    @Test
    func stdlibDependencyResolvesToBundledStdlib() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = try Self.makeUnpackedKlib(in: dir, name: "app", depends: ["stdlib"])

        let phase = DataFlowSemaPhase()
        let diagnostics = DiagnosticEngine()
        let appModule = try #require(phase.loadKlibModule(path: app.path, diagnostics: diagnostics))
        _ = phase.resolveKlibDependencies(
            [appModule], stdlibPresent: true, diagnostics: diagnostics
        )
        #expect(!diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0030" })

        let withoutStdlib = DiagnosticEngine()
        _ = phase.resolveKlibDependencies(
            [appModule], stdlibPresent: false, diagnostics: withoutStdlib
        )
        #expect(withoutStdlib.diagnostics.contains { $0.code == "KSWIFTK-LIB-0030" })
    }

    @Test
    func importLoopWarnsOnMissingKlibDependency() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Self.makeUnpackedKlib(in: dir, name: "app", depends: ["missinglib"])

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "KlibDepApp",
                emit: .kirDump,
                searchPaths: [dir.path]
            )
            let diagnostics = DiagnosticEngine()
            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: SymbolTable(),
                types: TypeSystem(),
                diagnostics: diagnostics,
                interner: StringInterner(),
                importedInlineFunctions: ImportedInlineFunctionStore()
            )
            // The manifest-only klib fails IR decode (LIB-0028) but the
            // dependency check still runs and reports the missing module.
            #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0030" })
        }
    }
}
