@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct IOBufferContractTests {
    private struct Index: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let ledger_count: Int
        let functions: [Function]
        let context_properties: [ContextProperty]
    }
    private struct Function: Decodable {
        struct Parameter: Decodable {
            let name: String
            let type: String
            let `default`: Bool
        }
        let fqName: String
        let visibility: String
        let receiver: String
        let signature: String
        let parameters: [Parameter]
        let effectiveDefaults: [Bool]
    }
    private struct ContextProperty: Decodable {
        let official_property: String
        let official_type: String
        let private_implementation: String
    }

    private func index() throws -> Index {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { directory.deleteLastPathComponent() }
        let result = try JSONDecoder().decode(Index.self, from: Data(contentsOf:
            directory.appendingPathComponent("Scripts/kotlinx_io_upstream/buffer/api-shapes.expected.json")))
        try #require(result.schemaVersion == 1 && result.ledger_count == 218)
        try #require(result.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(result.functions.count == 30 && result.context_properties.count == 3)
        return result
    }

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        if let artifact {
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                URL(fileURLWithPath: artifact).appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let result = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = result.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(result.options.includeStdlib == !library && result.options.stdlibLibraryPath == artifact)
        return result
    }

    @Test(arguments: [false, true])
    func publicBufferShapesAndDefaultsMatchTheRelease(library: Bool) throws {
        let expected = try index()
        let ctx = try context("fun main() = 0", library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let mangler = NameMangler()
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        func encoded(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: symbols, types: sema.types, nameResolver: resolve, unboxValueClasses: false)
        }
        for row in expected.functions {
            let matches = symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }.filter {
                    $0.kind == .function && !$0.flags.contains(.extensionMemberAlias)
                        && mangler.mangledSignature(for: $0, symbols: symbols, types: sema.types,
                            nameResolver: resolve, unboxValueClasses: false) == row.signature
                }
            try #require(matches.count == 1, "Exact Buffer overload \(row.fqName) \(row.signature)")
            let symbol = try #require(matches.first)
            let signature = try #require(symbols.functionSignature(for: symbol.id))
            #expect(symbol.visibility == .public && symbol.flags.contains(.importedLibrary) == library)
            #expect(signature.receiverType.map(encoded) == row.receiver)
            #expect(signature.parameterTypes.map(encoded) == row.parameters.map(\.type))
            #expect(signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == row.parameters.map(\.name))
            #expect(signature.valueParameterHasDefaultValues == row.effectiveDefaults)
            if row.fqName == "kotlinx.io.Buffer.get" { #expect(symbol.flags.contains(.operatorFunction)) }
            if row.fqName == "kotlinx.io.Buffer.hintEmit" {
                #expect(symbols.annotations(for: symbol.id).filter { $0.annotationFQName == "kotlinx.io.InternalIoApi" }.count == 1)
            }
        }
        let size = symbols.lookupAll(fqName: "kotlinx.io.Buffer.size".split(separator: ".").map { ctx.interner.intern(String($0)) })
            .compactMap { symbols.symbol($0) }.filter { $0.kind == .property }
        try #require(size.count == 1)
        let property = try #require(size.first)
        #expect(property.visibility == .public && !property.flags.contains(.mutable))
        #expect(encoded(try #require(symbols.propertyType(for: property.id))) == "J")
    }

    @Test(arguments: [false, true])
    func internalContextPropertiesHaveTypedGettersAndPrivateImplementations(library: Bool) throws {
        let ctx = try context("fun main() = 0", library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        // Source accessors become real functions during KIR construction;
        // an artifact imports their already-emitted accessor symbols at Sema.
        var sourceGetters: [KIRFunction] = []
        if !library {
            try BuildKIRPhase().run(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            sourceGetters = findAllKIRFunctions(in: try #require(ctx.kir))
        }
        let symbols = try #require(ctx.sema).symbols
        let sema = try #require(ctx.sema)
        let mangler = NameMangler()
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        var records: [MetadataRecord] = []
        if let path = ctx.options.stdlibLibraryPath {
            records = MetadataDecoder().decode(try String(contentsOf:
                URL(fileURLWithPath: path).appendingPathComponent("metadata.bin"), encoding: .utf8))
        }
        for row in try index().context_properties {
            let name = "kotlinx.io.unsafe." + row.official_property
            let all = symbols.lookupAll(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }
            let properties = all.filter { $0.kind == .property }
            try #require(properties.count == 1, "\(name) is a property rather than the old object classifier")
            #expect(all.allSatisfy { $0.kind == .property || $0.kind == .function })
            let property = try #require(properties.first)
            #expect(property.visibility == .internal && !property.flags.contains(.mutable))
            #expect(property.flags.contains(.importedLibrary) == library)
            let type = try #require(symbols.propertyType(for: property.id))
            #expect(mangler.encodeType(type, symbols: symbols, types: sema.types, nameResolver: resolve,
                unboxValueClasses: false) == "Lkotlinx.io.unsafe.\(row.official_type);")
            let getterID = symbols.extensionPropertyGetterAccessor(for: property.id)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property.id)
            #expect(symbols.propertyHasCustomGetter(for: property.id))
            let signature = try #require(symbols.functionSignature(for: getterID))
            #expect(signature.parameterTypes.isEmpty && signature.returnType == type && signature.receiverType == nil)
            if library {
                let getter = try #require(symbols.symbol(getterID), "An artifact must restore its emitted getter")
                #expect(getter.visibility == property.visibility && getter.visibility == .internal)
                #expect(getter.flags.contains(.importedLibrary))
                #expect(symbols.accessorOwnerProperty(for: getterID) == property.id)
            } else {
                let emitted = sourceGetters.filter { $0.symbol == getterID }
                try #require(emitted.count == 1, "The actual source property must emit one typed getter")
                let getter = try #require(emitted.first)
                #expect(getter.params.isEmpty && getter.returnType == type)
                #expect(getter.body.contains { instruction in
                    if case .returnValue = instruction { return true }
                    return false
                })
            }
            for annotation in ["kotlin.PublishedApi", "kotlinx.io.UnsafeIoApi"] {
                let entries = symbols.annotations(for: property.id).filter { $0.annotationFQName == annotation }
                #expect(entries.count == 1 && entries.allSatisfy { $0.arguments.isEmpty && $0.useSiteTarget == nil })
            }
            let getterMarkers = (symbols.annotations(for: property.id) + symbols.annotations(for: getterID))
                .filter { $0.annotationFQName == "kotlin.jvm.JvmSynthetic" }
            #expect(!getterMarkers.isEmpty && getterMarkers.allSatisfy {
                $0.arguments.isEmpty && ($0.useSiteTarget == nil || $0.useSiteTarget == "get")
            })
            if library {
                let record = try #require(records.first { $0.fqName == name && $0.kind == .property })
                #expect(record.visibility == .internal && record.propertyGetterExternalLinkName?.isEmpty == false)
                #expect(record.propertySetterExternalLinkName == nil)
                for item in records where item.fqName == "kotlinx.io.unsafe." + row.private_implementation {
                    #expect(item.visibility == .private, "Backing object must not become public/internal API")
                }
            } else {
                let implementations = symbols.lookupAll(fqName: ("kotlinx.io.unsafe." + row.private_implementation)
                    .split(separator: ".").map { ctx.interner.intern(String($0)) }).compactMap { symbols.symbol($0) }
                #expect(!implementations.isEmpty && implementations.allSatisfy { $0.visibility == .private })
            }
        }
    }

    @Test(arguments: [false, true], ["SegmentReadContextImpl", "SegmentWriteContextImpl", "BufferIterationContextImpl",
        "SegmentReadContextSingleton", "SegmentWriteContextSingleton", "BufferIterationContextSingleton"])
    func unsuppressedConsumersCannotAccessContextInternals(library: Bool, name: String) throws {
        let source = """
        @file:OptIn(kotlinx.io.UnsafeIoApi::class)
        import kotlinx.io.unsafe.*
        fun rejected() = \(name)
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "One isolated invisible value use must fail: \(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        var ranges: Set<SourceRange> = []
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .nameRef(value, _) = expr, ctx.interner.resolve(value) == name else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            ranges.insert(range)
            #expect(sema.bindings.identifierSymbol(for: id) == nil)
        }
        #expect(ranges.count == 1, "Actual rejected source occurrence must be present")
    }
}
