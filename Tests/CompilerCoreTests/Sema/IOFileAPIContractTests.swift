#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct IOFileAPIContractTests {
    private struct Index: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let rowCount: Int
        let canonicalRecordCount: Int
        let allowedExistingExtras: [Extra]
        let rows: [Row]
    }
    private struct Extra: Decodable {
        let fqName: String
        let kind: String
        let typeSignature: String
    }
    private struct Row: Decodable {
        let rowID: String
        let canonicalKey: String
        let upstreamRef: String
        let fqName: String
        let kind: String
        let visibility: String
        let receiverKind: String
        let receiverTypeSignature: String?
        let typeSignature: String?
        let parameterNames: [String]
        let parameterTypeSignatures: [String]
        let vararg: [Bool]
        let defaults: [Bool]
        let returnTypeSignature: String?
        let inline: Bool
        let operatorDeclared: Bool
        let `override`: Bool
        let typeParameterCount: Int
        let open: Bool
        let sealed: Bool
        let annotations: [Annotation]
        let superFQNames: [String]
        let getterSignature: String?
    }
    private struct Annotation: Decodable {
        struct Argument: Decodable {
            let name: String?
            let expression: String
        }
        let fqName: String
        let arguments: [Argument]
    }

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        #expect(ctx.options.stdlibLibraryPath == artifact)
        #expect(ctx.options.includeStdlib == !library)
        if let artifact {
            let url = URL(fileURLWithPath: artifact, isDirectory: true)
            let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
            #expect(manifest["formatVersion"] as? Int == 1)
            #expect(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        return ctx
    }

    private func checkPathProvenance(_ ctx: CompilationContext, library: Bool) throws {
        let sema = try #require(ctx.sema)
        let id = try #require(sema.symbols.lookupAll(fqName: ["kotlinx", "io", "files", "Path"].map { ctx.interner.intern($0) }).first {
            sema.symbols.symbol($0)?.kind == .class
        })
        #expect(sema.symbols.symbol(id)?.flags.contains(.importedLibrary) == library)
    }

    @Test(arguments: [false, true])
    func all41CommonNativeViewsMatch32Declarations(library: Bool) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/kotlinx_io_upstream/files/api-shapes.expected.json")
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture))
        #expect(index.schemaVersion == 1)
        #expect(index.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        #expect(index.rowCount == 41 && index.rows.count == 41)
        #expect(Set(index.rows.map(\.rowID)).count == 41)
        #expect(Set(index.rows.map(\.canonicalKey)).count == index.canonicalRecordCount)
        #expect(index.canonicalRecordCount == 32)
        let ctx = try context("fun main() = 0", library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        let mangler = NameMangler()
        func encode(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: symbols, types: sema.types, nameResolver: resolve, unboxValueClasses: false)
        }
        func signature(_ symbol: SemanticSymbol) -> String? {
            guard [.property, .constructor, .function].contains(symbol.kind) else { return nil }
            return mangler.mangledSignature(for: symbol, symbols: symbols, types: sema.types,
                                           nameResolver: resolve, unboxValueClasses: false)
        }
        var records: [MetadataRecord] = []
        if let path = ctx.options.stdlibLibraryPath {
            records = MetadataDecoder().decode(try String(contentsOfFile: path + "/metadata.bin", encoding: .utf8))
            #expect(!records.isEmpty)
        }
        var matched = Set<SymbolID>()
        for row in index.rows {
            let candidates = symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }.filter {
                    String(describing: $0.kind) == row.kind && !$0.flags.contains(.extensionMemberAlias)
                        && signature($0) == row.typeSignature
                }
            #expect(candidates.count == 1, "\(row.rowID) \(row.upstreamRef): \(candidates.count) candidates")
            let symbol = try #require(candidates.first)
            matched.insert(symbol.id)
            #expect(String(describing: symbol.visibility) == row.visibility)
            #expect(symbol.flags.contains(.importedLibrary) == library)
            #expect(!symbol.flags.contains(.memberExtension))
            #expect(!symbol.flags.contains(.inlineFunction) && row.inline == false)
            #expect(symbol.flags.contains(.operatorFunction) == row.operatorDeclared)
            #expect(symbol.flags.contains(.overrideMember) == row.override)
            if row.kind == "class" { #expect(symbol.flags.contains(.openType) == row.open) }
            if row.kind == "class" || row.kind == "interface" { #expect(symbol.flags.contains(.sealedType) == row.sealed) }
            if row.kind == "function" || row.kind == "constructor" {
                let fn = try #require(symbols.functionSignature(for: symbol.id))
                #expect(TypeCheckHelpers().declaresExtensionReceiver(symbol.id, sema: sema, interner: ctx.interner) == (row.receiverKind == "PACKAGE_EXTENSION"))
                #expect(fn.receiverType.map(encode) == row.receiverTypeSignature)
                #expect(fn.parameterTypes.map(encode) == row.parameterTypeSignatures)
                #expect(fn.valueParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == row.parameterNames)
                #expect(fn.valueParameterIsVararg == row.vararg)
                #expect(fn.valueParameterHasDefaultValues == row.defaults)
                #expect(encode(fn.returnType) == row.returnTypeSignature)
                #expect(fn.typeParameterSymbols.count == row.typeParameterCount)
                #expect(fn.contextReceiverTypes.isEmpty && !fn.isSuspend)
            }
            if row.kind == "property" {
                #expect(!symbol.flags.contains(.mutable) && !symbol.flags.contains(.constValue))
                #expect(symbols.extensionPropertyReceiverType(for: symbol.id) == nil)
                let propertyType = try #require(symbols.propertyType(for: symbol.id))
                #expect(encode(propertyType) == row.typeSignature)
                #expect(symbol.fqName.dropLast().map(resolve).joined(separator: ".") == row.fqName.split(separator: ".").dropLast().joined(separator: "."))
                #expect("F0<" + (row.receiverTypeSignature.map { "R" + $0 + "," } ?? "") + encode(propertyType) + ">" == row.getterSignature)
            }
            if row.kind == "class" || row.kind == "interface" {
                #expect(symbols.directSupertypes(for: symbol.id).compactMap { symbols.symbol($0)?.fqName.map(resolve).joined(separator: ".") }.sorted() == row.superFQNames.sorted())
            }
            try checkAnnotations(symbols.annotations(for: symbol.id), expected: row.annotations)
            if library {
                let emitted = records.filter { $0.fqName == row.fqName && String(describing: $0.kind) == row.kind && $0.typeSignature == row.typeSignature }
                #expect(emitted.count == 1, "\(row.rowID) must have one canonical emitted record")
                let record = try #require(emitted.first)
                try checkAnnotations(record.annotations, expected: row.annotations)
                if row.kind == "property" {
                    #expect(record.propertyGetterExternalLinkName?.isEmpty == false)
                    #expect(record.propertySetterExternalLinkName == nil && record.propertyReceiverTypeSignature == nil)
                    #expect(record.constValueLiteral == nil)
                }
                if row.defaults.contains(true) { #expect(record.defaultStubExternalLinkName?.isEmpty == false) }
            }
        }
        #expect(matched.count == 32)
        // Root explicitly retains these three pre-existing non-upstream APIs.
        // They cannot substitute for any of the 32 expected declarations.
        var retained = Set<SymbolID>()
        for extra in index.allowedExistingExtras {
            let found = symbols.lookupAll(fqName: extra.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }.filter { String(describing: $0.kind) == extra.kind && signature($0) == extra.typeSignature }
            #expect(found.count == 1, "Retained existing extra \(extra.fqName)")
            let extraSymbol = try #require(found.first)
            retained.insert(extraSymbol.id)
        }
        func hasPublicOwnerChain(_ symbol: SemanticSymbol) -> Bool {
            var current: SymbolID? = symbol.id
            var visited = Set<SymbolID>()
            while let id = current {
                guard visited.insert(id).inserted, let owner = symbols.symbol(id) else { return false }
                if owner.kind != .package && owner.visibility != .public && owner.visibility != .protected { return false }
                current = symbols.parentSymbol(for: id)
            }
            return true
        }
        let publicAPIs = symbols.allSymbols().filter { symbol in
            guard symbol.fqName.map(resolve).joined(separator: ".").hasPrefix("kotlinx.io.files."),
                  symbol.visibility == .public || symbol.visibility == .protected,
                  [.function, .constructor, .property, .class, .interface, .object, .enumClass, .annotationClass, .typeAlias].contains(symbol.kind),
                  !symbol.flags.contains(.extensionMemberAlias),
                  hasPublicOwnerChain(symbol),
                  symbols.propertySymbol(forAccessor: symbol.id) == nil,
                  symbols.accessorOwnerProperty(for: symbol.id) == nil else { return false }
            // Import reconstructs a companion initializer solely from the owner's metadata link.
            if symbol.flags == [.synthetic, .importedLibrary],
               let owner = symbols.parentSymbol(for: symbol.id), matched.contains(owner),
               symbols.companionObjectInitializerSymbol(for: owner) == symbol.id { return false }
            return true
        }
        #expect(Set(publicAPIs.map(\.id)) == matched.union(retained), "Unexpected APIs: \(publicAPIs.filter { !matched.contains($0.id) && !retained.contains($0.id) }.map { $0.fqName.map(resolve).joined(separator: ".") })")
    }

    @Test(arguments: [false, true])
    func legacyExtensionsResolveAndReportActualErrorDeprecations(library: Bool) throws {
        let ctx = try context("""
        import kotlinx.io.files.Path
        import kotlinx.io.files.source
        import kotlinx.io.files.sink
        fun read(path: Path) = path.source()
        fun write(path: Path) = path.sink()
        """, library: library)
        try? runSema(ctx)
        try checkPathProvenance(ctx, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-DEPRECATED" })
        #expect(errors.contains { $0.message.contains("Use FileSystem.source instead") })
        #expect(errors.contains { $0.message.contains("Use FileSystem.sink instead") })
    }

    @Test(arguments: [false, true])
    func ordinaryConsumerCannotCallInternalPathConstructor(library: Bool) throws {
        let ctx = try context("import kotlinx.io.files.Path\nfun forbidden() = Path(\"a\", true)", library: library)
        try? runSema(ctx)
        try checkPathProvenance(ctx, library: library)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [false, true])
    func systemFileSystemIsAValueNotANominalType(library: Bool) throws {
        let ctx = try context("import kotlinx.io.files.SystemFileSystem\nfun forbidden(value: SystemFileSystem) = value", library: library)
        try? runSema(ctx)
        try checkPathProvenance(ctx, library: library)
        #expect(ctx.diagnostics.hasError)
    }

    private func checkAnnotations(_ actual: [MetadataAnnotationRecord], expected: [Annotation]) throws {
        let declarations = actual.filter { $0.annotationFQName != "kotlin.Metadata" && $0.annotationFQName != "kotlin.OptIn" }
        #expect(Set(declarations.map(\.annotationFQName)) == Set(expected.map(\.fqName)))
        for annotation in expected {
            let record = try #require(declarations.first { $0.annotationFQName == annotation.fqName })
            #expect(record.useSiteTarget == nil && record.arguments.count == annotation.arguments.count)
            for (argument, observed) in zip(annotation.arguments, record.arguments) {
                let expression: String
                if let name = argument.name {
                    let parts = observed.split(separator: "=", maxSplits: 1)
                    #expect(parts.count == 2 && parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == name)
                    expression = parts.count == 2 ? String(parts[1]) : observed
                } else { expression = observed }
                #expect(canonicalExpression(expression) == canonicalExpression(argument.expression))
            }
        }
    }

    private func canonicalExpression(_ expression: String) -> String {
        var quoted = false
        var escaped = false
        var result = ""
        for char in expression {
            if quoted {
                result.append(char)
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { quoted = false }
            } else if char == "\"" {
                quoted = true
                result.append(char)
            } else if !char.isWhitespace { result.append(char) }
        }
        return result
    }
}
#endif
