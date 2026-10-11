#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct JVMInteropNioSourceContractsTests {
    private struct Index: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let functionCount: Int
        let rows: [Shape]
        let aliasNativeTargets: [String: String]
    }
    private struct Shape: Decodable {
        struct Annotation: Decodable {
            let fqName: String
            let sourceOnly: Bool
            let arguments: [String]
        }
        let rowID: String
        let upstreamRef: String
        let fqName: String
        let receiver: String
        let signature: String
        let parameters: [String]
        let parameterTypes: [String]
        let returnType: String
        let defaults: [Bool]
        let inline: Bool
        let callbackIndex: Int?
        let annotations: [Annotation]
    }
    private func index() throws -> Index {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let value = try JSONDecoder().decode(Index.self, from: Data(contentsOf: root.appendingPathComponent(
            "Scripts/kotlinx_io_upstream/jvm_interop/native-api-shapes.expected.json")))
        try #require(value.schemaVersion == 1 && value.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(value.functionCount == 28 && value.rows.count == 28 && Set(value.rows.map(\.rowID)).count == 28)
        return value
    }
    private func context(_ source: String, library: Bool) throws -> (CompilationContext, [String: String]?) {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(ctx.options.stdlibLibraryPath == artifact && ctx.options.includeStdlib == !library)
        guard let artifact else { return (ctx, nil) }
        let root = URL(fileURLWithPath: artifact, isDirectory: true)
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as? [String: Any])
        try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
        try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
        try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        return (ctx, try hashes(root))
    }
    private func hashes(_ root: URL) throws -> [String: String] {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: String] = [:]
        for case let file as URL in enumerator {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(file.path.dropFirst(base.path.count + 1))] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
        }
        return result
    }
    private func unchanged(_ ctx: CompilationContext, _ initial: [String: String]?) {
        guard let path = ctx.options.stdlibLibraryPath, let initial else { return }
        #expect((try? hashes(URL(fileURLWithPath: path, isDirectory: true))) == initial)
    }
    private func encodedSignature(_ symbol: SemanticSymbol, _ ctx: CompilationContext, _ sema: SemaModule) -> String {
        NameMangler().mangledSignature(for: symbol, symbols: sema.symbols, types: sema.types,
            nameResolver: ctx.interner.resolve, unboxValueClasses: false)
    }

    private struct DefaultObligations: Decodable {
        struct Row: Decodable {
            let rowID: String
            let fqName: String
            let parameterTokens: [String]
            let defaults: [Bool]
            let extensionReceiverToken: String?
            let visibility: String
        }
        let schemaVersion: Int
        let upstreamCommit: String
        let rowCount: Int
        let rows: [Row]
    }
    private func normalizeTypeParameterTokens(_ token: String) -> String {
        token.replacingOccurrences(of: "T-?[0-9]+", with: "T", options: .regularExpression)
    }

    @Test(arguments: [false, true])
    func all43NativeDefaultStubCounterpartsSurviveActualArtifact(library: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let index = try JSONDecoder().decode(DefaultObligations.self, from: Data(contentsOf: root.appendingPathComponent(
            "Scripts/kotlinx_io_upstream/jvm_interop/native-default-obligations.expected.json")))
        try #require(index.schemaVersion == 1 && index.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(index.rowCount == 43 && index.rows.count == 43 && Set(index.rows.map(\.rowID)).count == 43)
        let (ctx, initial) = try context("fun main() {}", library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let encode: (TypeID) -> String = { type in
            self.normalizeTypeParameterTokens(NameMangler().encodeType(type, symbols: sema.symbols, types: sema.types,
                nameResolver: ctx.interner.resolve, unboxValueClasses: false))
        }
        let records: [MetadataRecord]
        if let path = ctx.options.stdlibLibraryPath {
            records = MetadataDecoder().decode(try String(contentsOf: URL(fileURLWithPath: path)
                .appendingPathComponent("metadata.bin"), encoding: .utf8))
        } else { records = [] }
        for row in index.rows {
            let matches = sema.symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { sema.symbols.symbol($0) }.filter { symbol in
                    guard symbol.kind == .function, !symbol.flags.contains(.extensionMemberAlias),
                          let fn = sema.symbols.functionSignature(for: symbol.id),
                          fn.parameterTypes.map(encode) == row.parameterTokens else { return false }
                    if let receiver = row.extensionReceiverToken { return fn.receiverType.map(encode) == receiver }
                    return true
                }
            try #require(matches.count == 1, "\(row.rowID): \(row.fqName) \(row.parameterTokens)")
            let symbol = try #require(matches.first)
            let fn = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(fn.valueParameterHasDefaultValues == row.defaults, "\(row.rowID)")
            #expect(symbol.visibility == (row.visibility == "public" ? .public : .internal))
            #expect(symbol.flags.contains(.importedLibrary) == library)
            #expect(sema.symbols.isSourceBackedSymbol(symbol.id))
            if library {
                let signature = normalizeTypeParameterTokens(encodedSignature(symbol, ctx, sema))
                let exact = records.filter { $0.kind == .function && $0.fqName == row.fqName
                    && self.normalizeTypeParameterTokens($0.typeSignature ?? "") == signature }
                try #require(exact.count == 1, "Actual artifact: \(row.rowID)")
                let record = try #require(exact.first)
                #expect(record.valueParameterHasDefaultValues == row.defaults)
                #expect(record.valueParameterNames.count == row.defaults.count)
                #expect(record.defaultStubExternalLinkName?.isEmpty == false, "Actual Native default stub: \(row.rowID)")
            }
        }
    }

    @Test(arguments: [false, true])
    func all28OriginalNativeInteropShapesAndActualMetadata(library: Bool) throws {
        let expected = try index()
        let (ctx, initial) = try context("fun main() {}", library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        var records: [MetadataRecord] = []
        if let path = ctx.options.stdlibLibraryPath {
            records = MetadataDecoder().decode(try String(contentsOf: URL(fileURLWithPath: path)
                .appendingPathComponent("metadata.bin"), encoding: .utf8))
        }
        let encode: (TypeID) -> String = { NameMangler().encodeType($0, symbols: symbols, types: sema.types,
            nameResolver: ctx.interner.resolve, unboxValueClasses: false) }
        for row in expected.rows {
            let matching = symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }.filter {
                    $0.kind == .function && !$0.flags.contains(.extensionMemberAlias)
                        && encodedSignature($0, ctx, sema) == row.signature
                }
            try #require(matching.count == 1, "\(row.rowID) \(row.upstreamRef): \(row.signature)")
            let symbol = try #require(matching.first)
            let fn = try #require(symbols.functionSignature(for: symbol.id))
            #expect(symbol.visibility == .public && !symbol.flags.contains(.memberExtension))
            #expect(symbol.flags.contains(.importedLibrary) == library)
            #expect(symbols.isSourceBackedSymbol(symbol.id))
            #expect(!(symbols.externalLinkName(for: symbol.id) ?? "").hasPrefix("__kk_"))
            #expect(fn.receiverType.map(encode) == row.receiver)
            #expect(fn.parameterTypes.map(encode) == row.parameterTypes && encode(fn.returnType) == row.returnType)
            #expect(fn.valueParameterSymbols.compactMap { symbols.symbol($0).map { ctx.interner.resolve($0.name) } } == row.parameters)
            #expect(fn.valueParameterHasDefaultValues == row.defaults)
            #expect(fn.valueParameterIsVararg == Array(repeating: false, count: row.parameters.count))
            #expect(fn.typeParameterSymbols.isEmpty && !fn.isSuspend)
            #expect(symbol.flags.contains(.inlineFunction) == row.inline)
            let actual = symbols.annotations(for: symbol.id)
            let declarationAnnotations = actual.filter { !["kotlin.OptIn", "kotlin.Metadata"].contains($0.annotationFQName) }
            #expect(Set(declarationAnnotations.map(\.annotationFQName)) == Set(row.annotations.filter { !$0.sourceOnly }.map(\.fqName)))
            for annotation in row.annotations where !library || !annotation.sourceOnly {
                let values = actual.filter { $0.annotationFQName == annotation.fqName }
                try #require(values.count == 1)
                let value = try #require(values.first)
                #expect(value.useSiteTarget == nil && value.arguments.count == annotation.arguments.count)
                for (observed, pinned) in zip(value.arguments, annotation.arguments) {
                    #expect(observed.replacingOccurrences(of: "kotlinx.io.", with: "") == pinned)
                }
            }
            let effects = symbols.contractCallsInPlaceEffects(for: symbol.id)
            if let callback = row.callbackIndex {
                try #require(effects.count == 1)
                #expect(effects[0].kind == .exactlyOnce && effects[0].parameterSymbol == fn.valueParameterSymbols[callback])
                #expect(fn.valueParameterAllowsNonLocalReturn[callback])
            } else { #expect(effects.isEmpty) }
            if library {
                let matchingRecords = records.filter { $0.kind == .function && $0.fqName == row.fqName && $0.typeSignature == row.signature }
                try #require(matchingRecords.count == 1, "Actual artifact: \(row.rowID)")
                let record = try #require(matchingRecords.first)
                #expect(record.valueParameterNames == row.parameters && record.valueParameterHasDefaultValues == row.defaults)
                if row.defaults.contains(true) { #expect(record.defaultStubExternalLinkName?.isEmpty == false) }
            }
        }
        // Native uses common nominal classes plus reverse Java aliases. This
        // verifies exception identity, not a Java classfile alias facade.
        for (alias, target) in expected.aliasNativeTargets {
            let id = try #require(symbols.lookup(fqName: alias.split(separator: ".").map { ctx.interner.intern(String($0)) }))
            #expect(symbols.symbol(id)?.kind == .typeAlias)
            let underlying = try #require(symbols.typeAliasUnderlyingType(for: id))
            #expect(encode(underlying) == "L" + target + ";")
            #expect(symbols.symbol(id)?.flags.contains(.importedLibrary) == library)
            if library { #expect(records.contains { $0.kind == .typeAlias && $0.fqName == alias && $0.typeSignature == encode(underlying) }) }
        }
    }

    @Test(arguments: [false, true], [false, true])
    func explicitDefaultAndNamedCallsSelectExactImportedDeclarations(library: Bool, asAlias: Bool) throws {
        let getImport = asAlias ? "import kotlinx.io.bytestring.getByteString as readString" : "import kotlinx.io.bytestring.getByteString"
        let name = asAlias ? "readString" : "getByteString"
        let (ctx, initial) = try context("""
        import java.nio.ByteBuffer
        import java.io.InputStream
        import java.io.OutputStream
        import kotlinx.io.*
        import kotlinx.io.bytestring.*
        \(getImport)
        fun probe(buffer: Buffer, source: Source, sink: Sink, input: InputStream, output: OutputStream) {
            val nio = ByteBuffer.allocate(4)
            val a = nio.\(name)()
            val b = nio.\(name)(at = 1, length = 1)
            nio.putByteString(string = a)
            nio.putByteString(string = b, at = 0)
            a.asReadOnlyByteBuffer()
            buffer.readTo(out = output)
            buffer.copyTo(out = output, endIndex = 0L)
            source.readString(charset = Charsets.UTF_8, byteCount = 0L)
            sink.writeString(string = "x", charset = Charsets.UTF_8, endIndex = 1)
            a.decodeToString(Charsets.ISO_8859_1)
            source.asInputStream()
            sink.asOutputStream()
            input.asSource()
            output.asSink()
            buffer.asByteChannel()
        }
        """, library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let expected = try index()
        var count = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id), let symbol = sema.symbols.symbol(binding.chosenCallee),
                  expected.rows.contains(where: { $0.fqName == symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
                    && $0.signature == encodedSignature(symbol, ctx, sema) }) else { continue }
            let fn = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(symbol.flags.contains(.importedLibrary) == library)
            let args: [CallArgument]
            switch ast.arena.expr(id) {
            case let .memberCall(_, _, _, values, _): args = values
            default: Issue.record("Expected a direct member extension call"); continue
            }
            #expect(binding.parameterMapping.count == args.count)
            for (index, argument) in args.enumerated() {
                let parameter = try #require(binding.parameterMapping[index])
                if let label = argument.label { #expect(sema.symbols.symbol(fn.valueParameterSymbols[parameter])?.name == label) }
            }
            let supplied = Set(binding.parameterMapping.values)
            for parameter in fn.parameterTypes.indices where !supplied.contains(parameter) {
                #expect(fn.valueParameterHasDefaultValues[parameter])
            }
            count += 1
        }
        #expect(count == 15, "Every concrete call needs its exact declaration and named/default mapping")
    }

    @Test(arguments: [false, true], [0, 1, 2])
    func missingImportWrongCharsetAndPrivateBridgeAreRejected(library: Bool, control: Int) throws {
        let source = [
            "import java.nio.ByteBuffer\nfun bad(x: ByteBuffer) { x.getByteString() }",
            "import kotlinx.io.bytestring.*\nfun bad(x: ByteString) { x.decodeToString(1) }",
            "import kotlinx.io.kkKotlinSourceInputStream\nfun bad() {}",
        ][control]
        let (ctx, initial) = try context(source, library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error && $0.primaryRange.map { ctx.sourceManager.origin(of: $0.start.file) == .user } == true }
        #expect(!errors.isEmpty, "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0009" })
    }

    @Test(arguments: [false, true])
    func unsafeWarningAndExplicitOptInMatchOriginalContract(library: Bool) throws {
        for optedIn in [false, true] {
            let prefix = optedIn ? "@file:OptIn(kotlinx.io.UnsafeIoApi::class)\n" : ""
            let (ctx, initial) = try context(prefix + """
            import java.nio.ByteBuffer
            import kotlinx.io.Buffer
            import kotlinx.io.unsafe.UnsafeBufferOperations
            import kotlinx.io.unsafe.readFromHead
            fun probe(x: Buffer) { UnsafeBufferOperations.readFromHead(x) { _: ByteBuffer -> } }
            """, library: library)
            defer { unchanged(ctx, initial) }
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let warnings = ctx.diagnostics.diagnostics.filter { $0.severity == .warning && $0.message.contains("This is an unsafe API and its use requires care.") }
            #expect(warnings.count == (optedIn ? 0 : 1))
            if !optedIn { #expect(try #require(warnings.first).message.contains("Make sure you fully understand documentation of the declaration marked as UnsafeIoApi")) }
        }
    }
    @Test(arguments: [false, true])
    func sourceCharsetValuesAndPrivateCodecTagStayDistinctInKIR(library: Bool) throws {
        let (ctx, initial) = try context("""
        import java.nio.charset.Charset
        fun main(): ByteArray = "é".toByteArray(Charsets.ISO_8859_1)
        """, library: library)
        defer { unchanged(ctx, initial) }
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let calls = kirCalls(in: body)
        #expect(!calls.contains { ctx.interner.resolve($0.callee).hasPrefix("__kk_charset_") })
        let publicCall = try #require(calls.first { call in
            guard let id = call.symbol, let info = sema.symbols.symbol(id),
                  info.fqName.map(ctx.interner.resolve) == ["kotlin", "text", "toByteArray"],
                  let signature = sema.symbols.functionSignature(for: id) else { return false }
            return signature.parameterTypes.count == 1
        })
        try #require(publicCall.arguments.count == 2)
        let valueType = try #require(module.arena.exprType(publicCall.arguments[1]))
        guard case let .classType(value) = sema.types.kind(of: valueType) else {
            Issue.record("Public Charset must be a source object, not a codec Int"); return
        }
        #expect(sema.symbols.symbol(value.classSymbol)?.fqName.map(ctx.interner.resolve) == ["java", "nio", "charset", "Charset"])
        if !library {
            let codec = sema.symbols.allSymbols().filter {
                sema.symbols.externalLinkName(for: $0.id) == "__kk_string_toByteArray_charset_flat"
            }
            try #require(codec.count == 1)
            #expect(sema.symbols.functionSignature(for: codec[0].id)?.parameterTypes == [sema.types.intType])
        }
        // Artifact mode verifies the public imported source-object ABI above.
        // The executable fixture observes its private codec boundary; private
        // non-inline bridge declarations need not be exported to consumers.
    }

    @Test
    func sourceStreamFactoriesExpandAllClosuresAndRethrowAllNewFailureChannels() throws {
        let (ctx, initial) = try context("""
        import java.io.InputStream
        import java.io.OutputStream
        import java.io.BufferedWriter
        fun writerOperations(writer: BufferedWriter) { writer.close() }
        fun inputOperations(input: InputStream, data: ByteArray) {
            input.read(data, 0, 1)
            input.available()
            input.close()
            input.toString()
        }
        fun outputOperations(output: OutputStream, data: ByteArray) {
            output.write(data, 0, 1)
            output.close()
            output.toString()
        }
        """, library: false)
        defer { unchanged(ctx, initial) }
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let allCalls = findAllKIRFunctions(in: module).flatMap { kirCalls(in: $0.body) }
        for (callee, arity) in [("__kk_kotlin_source_input_stream", 10), ("__kk_kotlin_sink_output_stream_range", 8)] {
            let calls = allCalls.filter { ctx.interner.resolve($0.callee) == callee }
            try #require(calls.count == 1)
            #expect(calls[0].arguments.count == arity, "Every closure must retain its environment pair")
            guard case let .symbolRef(description)? = module.arena.expr(calls[0].arguments[arity - 2]) else {
                Issue.record("Description must use a generated Function0 entry"); continue
            }
            let adapter = try #require(findAllKIRFunctions(in: module).first { $0.symbol == description })
            #expect(adapter.returnType == ctx.sema?.types.anyType, "String callback returns one erased/boxed word, not a flat String aggregate")
        }
        let bodies = try ["inputOperations", "outputOperations", "writerOperations"].map {
            try findKIRFunctionBody(named: $0, in: module, interner: ctx.interner)
        }
        let required: Set<String> = ["__kk_input_stream_read_range", "__kk_output_stream_write_range",
            "__kk_input_stream_available_throwing", "__kk_input_stream_close_throwing", "__kk_output_stream_close_throwing",
            "__kk_buffered_writer_close_throwing", "__kk_io_stream_to_string"]
        var seen = Set<String>()
        for body in bodies {
            for instruction in body {
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction,
                      required.contains(ctx.interner.resolve(callee)) else { continue }
                #expect(canThrow)
                let thrown = try #require(thrownResult)
                #expect(body.contains { if case let .rethrow(value) = $0 { return value == thrown }; return false })
                seen.insert(ctx.interner.resolve(callee))
            }
        }
        #expect(seen == required)
    }

    @Test(arguments: [false, true])
    func jvmAnnotationsAndNativeGetterLinksSurviveTheActualArtifact(library: Bool) throws {
        let (ctx, initial) = try context("fun main() {}", library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let propertyCases: [(String, String, [String?])] = [
            ("kotlinx.io.Buffer.head", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Buffer.tail", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Buffer.sizeMut", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Segment.pos", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Segment.limit", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Segment.next", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Segment.prev", "kotlin.jvm.JvmSynthetic", ["get", "set"]),
            ("kotlinx.io.Segment.owner", "kotlin.jvm.JvmField", [nil]),
            ("kotlinx.io.RealSource.closed", "kotlin.jvm.JvmField", [nil]),
            ("kotlinx.io.RealSink.closed", "kotlin.jvm.JvmField", [nil]),
            ("kotlinx.io.unsafe.SegmentReadContextImpl", "kotlin.jvm.JvmSynthetic", ["get"]),
            ("kotlinx.io.unsafe.SegmentWriteContextImpl", "kotlin.jvm.JvmSynthetic", ["get"]),
            ("kotlinx.io.unsafe.BufferIterationContextImpl", "kotlin.jvm.JvmSynthetic", ["get"]),
            ("java.nio.ByteBuffer.isReadOnly", "kotlin.jvm.JvmName", ["get"]),
            ("java.nio.ByteBuffer.isDirect", "kotlin.jvm.JvmName", ["get"]),
            ("java.nio.channels.Channel.isOpen", "kotlin.jvm.JvmName", ["get"]),
        ]
        var records: [MetadataRecord] = []
        if let path = ctx.options.stdlibLibraryPath {
            records = MetadataDecoder().decode(try String(contentsOf: URL(fileURLWithPath: path)
                .appendingPathComponent("metadata.bin"), encoding: .utf8))
        }
        for (name, annotation, targets) in propertyCases {
            let properties = sema.symbols.lookupAll(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .property }
            try #require(properties.count == 1, name)
            let property = try #require(properties.first)
            #expect(property.flags.contains(.importedLibrary) == library)
            let values = sema.symbols.annotations(for: property.id).filter { $0.annotationFQName == annotation }
            #expect(values.map(\.useSiteTarget).sorted { ($0 ?? "") < ($1 ?? "") } == targets.sorted { ($0 ?? "") < ($1 ?? "") })
            if annotation == "kotlin.jvm.JvmName" {
                #expect(values.first?.arguments == ["\"" + String(name.split(separator: ".").last!) + "\""])
            }
            if library {
                let actual = records.filter { $0.kind == .property && $0.fqName == name }
                try #require(actual.count == 1, "Actual artifact: " + name)
                #expect(actual[0].annotations.filter { $0.annotationFQName == annotation } == values)
                if annotation == "kotlin.jvm.JvmName" || name.hasSuffix("ContextImpl") {
                    #expect(actual[0].propertyGetterExternalLinkName?.isEmpty == false)
                }
            }
        }
        for name in ["kotlinx.io.Buffer.writableSegment", "kotlinx.io.Buffer.recycleTail", "kotlinx.io.seek", "kotlinx.io.unsafe.withData"] {
            let symbols = sema.symbols.lookupAll(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .function && !$0.flags.contains(.extensionMemberAlias) }
            try #require(symbols.count == 1, name)
            let symbol = try #require(symbols.first)
            #expect(sema.symbols.annotations(for: symbol.id).contains { $0.annotationFQName == "kotlin.jvm.JvmSynthetic" && $0.useSiteTarget == nil })
            if library {
                #expect(records.contains { $0.kind == .function && $0.fqName == name && $0.annotations.contains { $0.annotationFQName == "kotlin.jvm.JvmSynthetic" } })
            }
        }
    }

    @Test(arguments: [false, true])
    func memoryStreamConstructorsBindToByteArrayAndThrowingCapacityABI(library: Bool) throws {
        let (ctx, initial) = try context("""
        import java.io.ByteArrayInputStream
        import java.io.ByteArrayOutputStream
        import java.nio.ByteBuffer
        fun probe(bytes: ByteArray) {
            val nio = ByteBuffer.allocate(bytes.size)
            nio[bytes]
            nio[0]
            ByteArrayInputStream(bytes)
            ByteArrayOutputStream()
            ByteArrayOutputStream(0)
        }
        """, library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var seen: Set<String> = []
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.origin(of: range.start.file) == .user,
                  let call = sema.bindings.callBinding(for: id),
                  let link = sema.symbols.externalLinkName(for: call.chosenCallee),
                  ["__kk_bytearrayinputstream_new", "__kk_bytearray_output_stream_new_default", "__kk_bytearray_output_stream_new"].contains(link) else { continue }
            let signature = try #require(sema.symbols.functionSignature(for: call.chosenCallee))
            if link == "__kk_bytearrayinputstream_new" {
                try #require(signature.parameterTypes.count == 1)
                #expect(NameMangler().encodeType(signature.parameterTypes[0], symbols: sema.symbols, types: sema.types,
                    nameResolver: ctx.interner.resolve, unboxValueClasses: false) == "Lkotlin.ByteArray;")
            } else if link == "__kk_bytearray_output_stream_new" { #expect(signature.parameterTypes == [sema.types.intType]) }
            else { #expect(signature.parameterTypes.isEmpty) }
            seen.insert(link)
        }
        #expect(seen == ["__kk_bytearrayinputstream_new", "__kk_bytearray_output_stream_new_default", "__kk_bytearray_output_stream_new"])
    }

    @Test(arguments: [false, true])
    func realFileChannelAndOriginalBufferCastProducersBindFromSourceAndArtifact(library: Bool) throws {
        let (ctx, initial) = try context("""
        import java.nio.ByteBuffer
        import java.nio.Buffer
        import java.nio.channels.FileChannel
        import java.nio.file.Paths
        import java.nio.file.StandardOpenOption
        import kotlin.io.path.createFile
        import kotlin.io.path.inputStream
        import kotlinx.io.asSource
        import kotlinx.io.buffered
        fun probe() {
            val path = Paths.get("/tmp", "kuu1762").createFile()
            val channel = FileChannel.open(path, StandardOpenOption.READ)
            val data = ByteBuffer.allocate(2)
            (data as Buffer).flip()
            channel.read(data)
            channel.close()
            path.inputStream().asSource().buffered().close()
        }
        """, library: library)
        defer { unchanged(ctx, initial) }
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for name in ["java.nio.Buffer", "java.nio.channels.FileChannel", "java.nio.file.Path"] {
            let matches = sema.symbols.lookupAll(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .class }
            let symbol = try #require(matches.first)
            #expect(matches.count == 1 && sema.symbols.isSourceBackedSymbol(symbol.id))
            #expect(symbol.flags.contains(.importedLibrary) == library)
        }
    }

    @Test(arguments: [false, true])
    func streamDescriptionsAndSequenceCompositionCarryNativeErrorChannels(library: Bool) throws {
        let (ctx, initial) = try context("""
        import java.io.InputStream
        import java.io.SequenceInputStream
        fun probe(a: InputStream, b: InputStream): String {
            val chain = SequenceInputStream(a, b)
            chain.read()
            chain.available()
            chain.close()
            return a.toString()
        }
        fun objectInterpolation(a: Any): String = "<$a>"
        """, library: library)
        defer { unchanged(ctx, initial) }
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        for name in ["__kk_io_stream_to_string", "__kk_sequence_input_stream_read", "__kk_sequence_input_stream_available_throwing", "__kk_sequence_input_stream_close_throwing"] {
            let calls = kirCalls(in: body).filter { ctx.interner.resolve($0.callee) == name }
            try #require(calls.count == 1)
            #expect(calls[0].canThrow && calls[0].thrownResult != nil)
        }
        let interpolation = try findKIRFunctionBody(named: "objectInterpolation", in: module, interner: ctx.interner)
        let converted = try #require(kirCalls(in: interpolation).first { ctx.interner.resolve($0.callee) == "__kk_any_to_string_throwing" })
        #expect(converted.canThrow && converted.thrownResult != nil)
        #expect(interpolation.contains { if case .rethrow = $0 { return true }; return false })
    }

}
#endif
