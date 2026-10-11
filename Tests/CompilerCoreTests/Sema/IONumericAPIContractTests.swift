#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct IONumericAPIContractTests {
    private struct Index: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let commonLedgerCount: Int
        let neighborControlCount: Int
        let optInRetention: String
        let rows: [Shape]
    }
    private struct Shape: Decodable {
        struct Parameter: Decodable {
            let name: String
            let type: String
            let `default`: Bool
            let defaultExpression: String?
        }
        let rowID: String
        let fqName: String
        let visibility: String
        let receiver: String
        let signature: String
        let parameters: [Parameter]
        let optInArguments: [String]
        let sourceOnly: Bool
        let abstract: Bool
        let upstreamRef: String
        let scope: String
    }

    private func root() -> URL {
        var result = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { result.deleteLastPathComponent() }
        return result
    }

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(ctx.options.stdlibLibraryPath == artifact)
        try #require(ctx.options.includeStdlib == !library)
        return ctx
    }

    @Test(arguments: [false, true])
    func commonNumericAndArrayMetadataMatchesOfficialSource(library: Bool) throws {
        let fixture = root().appendingPathComponent("Scripts/kotlinx_io_upstream/numeric/api-shapes.expected.json")
        let pinned = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture))
        try #require(pinned.schemaVersion == 1)
        try #require(pinned.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(pinned.commonLedgerCount == 46 && pinned.neighborControlCount == 6)
        try #require(pinned.rows.count == 52 && Set(pinned.rows.map(\.rowID)).count == 52)
        try #require(pinned.rows.filter { $0.scope == "KUU1731_COMMON_LEDGER" }.count == 46)
        // Kotlin 2.3.10 OptIn is SOURCE retention, not a library annotation.
        try #require(pinned.optInRetention == "SOURCE")
        let ctx = try context("fun main() = 0", library: library)
        var records: [MetadataRecord] = []
        if library {
            let path = try #require(ctx.options.stdlibLibraryPath)
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let manifest = try #require(JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            ) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
            records = MetadataDecoder().decode(try String(
                contentsOf: directory.appendingPathComponent("metadata.bin"), encoding: .utf8
            ))
            try #require(!records.isEmpty)
        }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        let mangler = NameMangler()
        func encoded(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: symbols, types: sema.types,
                               nameResolver: resolve, unboxValueClasses: false)
        }
        for row in pinned.rows {
            if library && row.sourceOnly {
                for record in records where record.fqName == row.fqName {
                    #expect(record.visibility == .private, "Private helper may never be exported as public")
                }
                continue
            }
            let observed = symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == .function && !$0.flags.contains(.extensionMemberAlias)
                    && mangler.mangledSignature(for: $0, symbols: symbols, types: sema.types,
                                                nameResolver: resolve, unboxValueClasses: false) == row.signature }
            try #require(observed.count == 1, "\(row.rowID) \(row.upstreamRef): expected exact overload \(row.signature)")
            let symbol = try #require(observed.first)
            let signature = try #require(symbols.functionSignature(for: symbol.id))
            #expect(String(describing: symbol.visibility) == row.visibility, "\(row.rowID) visibility")
            #expect(symbol.flags.contains(.importedLibrary) == library, "Actual requested producer mode")
            #expect(signature.receiverType.map(encoded) == row.receiver, "\(row.rowID) receiver")
            #expect(signature.parameterTypes.map(encoded) == row.parameters.map(\.type))
            #expect(signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == row.parameters.map(\.name))
            #expect(signature.valueParameterHasDefaultValues == row.parameters.map(\.default))
            #expect(signature.valueParameterIsVararg == Array(repeating: false, count: row.parameters.count))
            #expect(signature.typeParameterSymbols.isEmpty && !signature.isSuspend)
            let optIn = symbols.annotations(for: symbol.id).filter { $0.annotationFQName == "kotlin.OptIn" }
            if library || row.optInArguments.isEmpty {
                #expect(optIn.isEmpty, "\(row.rowID) exact SOURCE-retention boundary")
            } else {
                try #require(optIn.count == 1, "\(row.rowID) official OptIn")
                let annotation = try #require(optIn.first)
                #expect(annotation.useSiteTarget == nil)
                #expect(annotation.arguments.map(canonicalMarker) == row.optInArguments.map(canonicalMarker),
                        "\(row.rowID) exact marker class literals and order")
            }
            if library {
                let record = try #require(records.first { $0.fqName == row.fqName && $0.typeSignature == row.signature })
                #expect(record.valueParameterNames == row.parameters.map(\.name))
                #expect(record.valueParameterHasDefaultValues == row.parameters.map(\.default))
                if !row.abstract && row.parameters.contains(where: { $0.default }) {
                    #expect(record.defaultStubExternalLinkName?.isEmpty == false, "Actual default stub must cross artifact boundary")
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func privateArrayImplementationIsNotCallableByConsumer(library: Bool) throws {
        let ctx = try context("""
        import kotlinx.io.*
        fun illegal(source: Source): ByteArray = source.readByteArrayImpl(1)
        """, library: library)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        var ranges: Set<SourceRange> = []
        for (index, expression) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, _) = expression,
                  ctx.interner.resolve(name) == "readByteArrayImpl" else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            ranges.insert(range)
            #expect(sema.bindings.callBinding(for: id) == nil)
        }
        #expect(ranges.count == 1)
    }

    private func canonicalMarker(_ value: String) -> String {
        let text = value.replacingOccurrences(of: " ", with: "")
        // Exact official imported marker identities only; no suffix matching.
        let names = ["InternalIoApi", "DelicateIoApi", "UnsafeIoApi"]
        for name in names where text == name + "::class" { return "kotlinx.io." + text }
        if text == "UnsafeByteStringApi::class" { return "kotlinx.io.bytestring.unsafe." + text }
        return text
    }
}
#endif
