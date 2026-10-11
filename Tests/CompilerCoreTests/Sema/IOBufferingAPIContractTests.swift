#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct IOBufferingAPIContractTests {
    private struct Index: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let rows: [Shape]
    }
    private struct Shape: Decodable {
        struct Parameter: Decodable {
            let name: String
            let type: String
            let `default`: Bool
            let defaultExpression: String?
        }
        let fqName: String
        let visibility: String
        let receiver: String?
        let signature: String
        let parameters: [Parameter]
        let annotationFQNames: [String]
        let upstreamRef: String
    }

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(ctx.options.stdlibLibraryPath == artifact && ctx.options.includeStdlib == !library)
        return ctx
    }

    @Test(arguments: [false, true])
    func officialBufferingSignaturesDefaultsAndAnnotations(library: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let fixture = root.appendingPathComponent("Scripts/kotlinx_io_upstream/buffering/api-shapes.expected.json")
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture))
        try #require(index.schemaVersion == 1 && index.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(index.rows.count == 30)
        let ctx = try context("fun main() = 0", library: library)
        var records: [MetadataRecord] = []
        if library {
            let directory = URL(fileURLWithPath: try #require(ctx.options.stdlibLibraryPath), isDirectory: true)
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            records = MetadataDecoder().decode(try String(contentsOf: directory.appendingPathComponent("metadata.bin"), encoding: .utf8))
        }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        let mangler = NameMangler()
        func encode(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: symbols, types: sema.types, nameResolver: resolve, unboxValueClasses: false)
        }
        for row in index.rows {
            let matching = symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }.filter {
                    $0.kind == .function && !$0.flags.contains(.extensionMemberAlias)
                        && mangler.mangledSignature(for: $0, symbols: symbols, types: sema.types, nameResolver: resolve, unboxValueClasses: false) == row.signature
                }
            try #require(matching.count == 1, "\(row.upstreamRef): exact overload \(row.signature)")
            let symbol = try #require(matching.first)
            let signature = try #require(symbols.functionSignature(for: symbol.id))
            #expect(String(describing: symbol.visibility) == row.visibility)
            #expect(symbol.flags.contains(.importedLibrary) == library)
            #expect(signature.receiverType.map(encode) == row.receiver)
            #expect(signature.parameterTypes.map(encode) == row.parameters.map(\.type))
            #expect(signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == row.parameters.map(\.name))
            #expect(signature.valueParameterHasDefaultValues == row.parameters.map(\.default))
            #expect(signature.valueParameterIsVararg == Array(repeating: false, count: row.parameters.count))
            let annotations = symbols.annotations(for: symbol.id).filter {
                $0.annotationFQName == "kotlinx.io.InternalIoApi" || $0.annotationFQName == "kotlin.IgnorableReturnValue"
            }
            #expect(annotations.map(\.annotationFQName) == row.annotationFQNames, "Exact annotation identity; BINARY survives the actual artifact")
            #expect(annotations.allSatisfy { $0.arguments.isEmpty && $0.useSiteTarget == nil })
            if library {
                let record = try #require(records.first { $0.fqName == row.fqName && $0.typeSignature == row.signature })
                #expect(record.valueParameterNames == row.parameters.map(\.name))
                #expect(record.valueParameterHasDefaultValues == row.parameters.map(\.default))
            }
        }
        for owner in ["Source", "Sink"] {
            let types = symbols.lookupAll(fqName: ["kotlinx", "io", owner].map { ctx.interner.intern($0) })
                .compactMap { symbols.symbol($0) }.filter { $0.kind == .interface }
            try #require(types.count == 1)
            #expect(types[0].visibility == .public && types[0].flags.contains(.sealedType))
            #expect(types[0].flags.contains(.importedLibrary) == library)
            let fqName = "kotlinx.io." + owner + ".buffer"
            let properties = symbols.lookupAll(fqName: fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }.filter { $0.kind == .property }
            try #require(properties.count == 1)
            let property = try #require(properties.first)
            #expect(property.visibility == .public && !property.flags.contains(.mutable))
            #expect(property.flags.contains(.importedLibrary) == library)
            #expect(encode(try #require(symbols.propertyType(for: property.id))) == "Lkotlinx.io.Buffer;")
            let annotations = symbols.annotations(for: property.id).filter { $0.annotationFQName == "kotlinx.io.InternalIoApi" }
            try #require(annotations.count == 1)
            #expect(annotations[0].arguments.isEmpty && annotations[0].useSiteTarget == nil)
        }
    }

    @Test(arguments: [false, true])
    func userRawSubtypesResolveInheritedAndDefaultCalls(library: Bool) throws {
        let ctx = try context("""
        @file:OptIn(kotlinx.io.InternalIoApi::class)
        package kuu1730core
        import kotlinx.io.*
        class UserSource : RawSource {
            override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
            override fun close() {}
        }
        class UserSink : RawSink {
            override fun write(source: Buffer, byteCount: Long) {}
            override fun flush() {}
            override fun close() {}
        }
        fun selected(source: Source, sink: Sink, buffer: Buffer): Int {
            val rawSource: RawSource = UserSource()
            val rawSink: RawSink = UserSink()
            val wrappedSource: Source = rawSource.buffered()
            val wrappedSink: Sink = rawSink.buffered()
            rawSource.readAtMostTo(buffer, 1L)
            source.readAtMostTo(buffer, 1L)
            buffer.readAtMostTo(Buffer(), 1L)
            rawSink.write(buffer, 0L)
            sink.write(buffer, 0L)
            wrappedSource.readAtMostTo(ByteArray(2))
            source.readAtMostTo(ByteArray(2), endIndex = 1)
            wrappedSink.write(ByteArray(2))
            sink.write(ByteArray(2), endIndex = 1)
            return 0
        }
        """, library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        var ranges: Set<SourceRange> = []
        var fqNames: [String] = []
        for (index, expression) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, _) = expression,
                  ["readAtMostTo", "write", "buffered"].contains(ctx.interner.resolve(name)) else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.path(of: range.start.file) == path,
                  sema.bindings.exprType(for: id) != nil else { continue }
            guard ranges.insert(range).inserted else { continue }
            let binding = try #require(sema.bindings.callBinding(for: id))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            fqNames.append(symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: "."))
        }
        #expect(ranges.count == 11)
        #expect(fqNames.filter { $0 == "kotlinx.io.RawSource.readAtMostTo" }.count == 2)
        #expect(fqNames.filter { $0 == "kotlinx.io.Buffer.readAtMostTo" }.count == 1)
        #expect(fqNames.filter { $0 == "kotlinx.io.Source.readAtMostTo" }.count == 2)
        #expect(fqNames.filter { $0 == "kotlinx.io.buffered" }.count == 2)
        #expect(fqNames.filter { $0 == "kotlinx.io.RawSink.write" }.count == 2)
        #expect(fqNames.filter { $0 == "kotlinx.io.Sink.write" }.count == 2)
    }

    @Test(arguments: [false, true])
    func nativeEOFConstructorsKeepExactPublicNullableShape(library: Bool) throws {
        let ctx = try context("""
        package kuu1730eofcore
        import kotlinx.io.EOFException
        import kotlinx.io.IOException
        class Child(message: String?, cause: Throwable?) : EOFException(message, cause)
        fun make(root: Throwable?): EOFException = EOFException(cause = root, message = null)
        fun view(root: Throwable?): IOException = make(root)
        """, library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let fqName = ["kotlinx", "io", "EOFException"].map { ctx.interner.intern($0) }
        let owner = try #require(symbols.lookup(fqName: fqName))
        let ownerInfo = try #require(symbols.symbol(owner))
        #expect(ownerInfo.kind == .class && ownerInfo.visibility == .public)
        #expect(ownerInfo.flags.contains(.openType) && ownerInfo.flags.contains(.importedLibrary) == library)
        let base = try #require(symbols.lookup(fqName: ["kotlinx", "io", "IOException"].map { ctx.interner.intern($0) }))
        #expect(symbols.directSupertypes(for: owner).contains(base))
        let throwable = try #require(symbols.lookup(fqName: ["kotlin", "Throwable"].map { ctx.interner.intern($0) }))
        let ownerType = sema.types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))
        let nullableCause = sema.types.make(.classType(ClassType(classSymbol: throwable, args: [], nullability: .nullable)))
        let nullableMessage = sema.types.makeNullable(sema.types.stringType)
        let constructors = symbols.lookupAll(fqName: fqName + [ctx.interner.intern("<init>")])
            .compactMap { symbols.symbol($0) }.filter { $0.kind == .constructor }
        try #require(constructors.count == 3, "Native has noarg/message/message+cause, no cause-only or synthetic extra constructor")
        let expectedTypes: [[TypeID]] = [[], [nullableMessage], [nullableMessage, nullableCause]]
        let expectedNames = [[], ["message"], ["message", "cause"]]
        var records: [MetadataRecord] = []
        if let path = ctx.options.stdlibLibraryPath {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                directory.appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
            records = MetadataDecoder().decode(try String(contentsOf:
                directory.appendingPathComponent("metadata.bin"), encoding: .utf8))
            let ownerRecord = try #require(records.first { $0.kind == .class && $0.fqName == "kotlinx.io.EOFException" })
            #expect(ownerRecord.visibility == .public && ownerRecord.isOpenClass)
        }
        let mangler = NameMangler()
        for (parameterTypes, names) in zip(expectedTypes, expectedNames) {
            let matches = constructors.filter { symbols.functionSignature(for: $0.id)?.parameterTypes == parameterTypes }
            try #require(matches.count == 1, "Exact Native EOF constructor parameter types")
            let constructor = try #require(matches.first)
            let signature = try #require(symbols.functionSignature(for: constructor.id))
            #expect(constructor.visibility == .public && constructor.flags.contains(.importedLibrary) == library)
            #expect(signature.receiverType == ownerType && signature.returnType == ownerType)
            #expect(signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { ctx.interner.resolve($0.name) } } == names)
            #expect(signature.valueParameterHasDefaultValues == Array(repeating: false, count: parameterTypes.count))
            #expect(signature.valueParameterIsVararg == Array(repeating: false, count: parameterTypes.count))
            if library {
                let encoded = mangler.mangledSignature(for: constructor, symbols: symbols, types: sema.types,
                    nameResolver: { ctx.interner.resolve($0) }, unboxValueClasses: false)
                let matchingRecords = records.filter {
                    $0.kind == .constructor && $0.fqName == "kotlinx.io.EOFException.<init>" && $0.typeSignature == encoded
                }
                try #require(matchingRecords.count == 1)
                let record = try #require(matchingRecords.first)
                #expect(record.visibility == .public && record.arity == parameterTypes.count)
                #expect(record.valueParameterNames == names && record.valueParameterHasDefaultValues == Array(repeating: false, count: names.count))
                #expect(record.externalLinkName?.isEmpty == false && record.defaultStubExternalLinkName == nil)
            } else {
                #expect(symbols.isSourceBackedSymbol(constructor.id))
            }
        }
    }

    @Test(arguments: [false, true])
    func implementationTypesStayInaccessibleToIndependentConsumer(library: Bool) throws {
        for body in ["RealSource(Buffer())", "RealSink(Buffer())", "PeekSource(Buffer())", "DiscardingSink()"] {
            let ctx = try context("package independentconsumer\nimport kotlinx.io.*\nfun illegal() = \(body)", library: library)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Each distinct internal/private constructor must be rejected: \(body)")
            let sema = try #require(ctx.sema)
            let typeName = String(body.prefix { $0 != "(" })
            let candidates = sema.symbols.lookupAll(fqName: ["kotlinx", "io", typeName].map { ctx.interner.intern($0) })
                .compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .class }
            // A producer may omit unused private declarations; a present record
            // must retain its official visibility, never become public.
            if !library { try #require(!candidates.isEmpty) }
            #expect(candidates.allSatisfy { $0.visibility == (typeName == "DiscardingSink" ? .private : .internal) })
        }
        // This checks independent rejection, not diagnostic codes or statement ranges.
    }
}
#endif
