#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct ByteStringBuilderContractTests {
    private var unsafeWarning: String {
        "This is a unsafe API and its use may corrupt the data stored in a byte string. "
            + "Make sure you fully read and understand documentation of the declaration that is marked as an unsafe API."
    }


    /// Sema tests use kirDump, whose process-default artifact lookup is intentionally disabled.
    /// Pass the published path explicitly and verify the actual imported declarations afterward.
    private func makeContractContext(_ source: String, allowDefaultStdlibLibrary: Bool) throws -> CompilationContext {
        let selectedLibrary = allowDefaultStdlibLibrary
            ? try #require(CompilerOptions.defaultStdlibLibraryPath, "Shared stdlib artifact must be published") : nil
        let inputPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [inputPath], stdlibLibraryPath: selectedLibrary,
                                         allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: inputPath, contents: Data(source.utf8))
        #expect(ctx.options.stdlibLibraryPath == selectedLibrary)
        #expect(ctx.options.includeStdlib == !allowDefaultStdlibLibrary)
        if let selectedLibrary {
            let directory = URL(fileURLWithPath: selectedLibrary, isDirectory: true)
            let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
            #expect(manifest["formatVersion"] as? Int == 1)
            #expect(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        return ctx
    }

    private func checkContractProvenance(_ ctx: CompilationContext, library: Bool) throws {
        let sema = try #require(ctx.sema)
        for name in ["kotlinx.io.bytestring.ByteStringBuilder", "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi"] {
            let id = try #require(sema.symbols.lookupAll(fqName: name.split(separator: ".").map {
                ctx.interner.intern(String($0))
            }).first { sema.symbols.symbol($0)?.kind == .class || sema.symbols.symbol($0)?.kind == .annotationClass })
            #expect(sema.symbols.symbol(id)?.flags.contains(.importedLibrary) == library,
                    "\(name) must come from the requested source/library mode")
        }
    }

    @Test(arguments: [true, false])
    func builderExtensionsRequireImport(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("""
        import kotlinx.io.bytestring.ByteStringBuilder
        import kotlinx.io.bytestring.ByteString
        fun use(builder: ByteStringBuilder) {
            builder.append(ByteString())
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test(arguments: [true, false])
    func implicitBuilderExtensionsRequireImport(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("""
        import kotlinx.io.bytestring.ByteStringBuilder
        fun ByteStringBuilder.use() {
            append(128U)
            append(1, 2, 3)
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 2,
                "Both unimported extensions must fail: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [true, false])
    func builderHasNoExtraToByteArrayMember(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("""
        import kotlinx.io.bytestring.ByteStringBuilder
        fun use(builder: ByteStringBuilder) = builder.toByteArray()
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0024" })
    }

    @Test(arguments: [true, false])
    func unsafeAccessRequiresErrorLevelOptIn(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("""
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations
        fun use() = UnsafeByteStringOperations.wrapUnsafe(byteArrayOf(1))
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try? runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("UnsafeByteStringApi")
        }
        #expect(!diagnostics.isEmpty)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
        #expect(diagnostics.allSatisfy { $0.message.contains(unsafeWarning) })
    }

    @Test(arguments: [true, false])
    func publishedBackingArrayRemainsInternal(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("""
        import kotlinx.io.bytestring.ByteString
        fun use(bytes: ByteString) = bytes.getBackingArrayReference()
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try? runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [true, false])
    func byteStringAnnotationsSurviveSourceAndLibraryImport(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("fun main() = 0", allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        let sema = try #require(ctx.sema)
        func symbols(_ name: String) -> [SymbolID] {
            sema.symbols.lookupAll(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) })
        }
        func annotated(_ id: SymbolID, _ name: String) -> Bool {
            sema.symbols.annotations(for: id).contains {
                $0.annotationFQName == name || $0.annotationFQName.hasSuffix("." + name)
            }
        }
        let emptyFactory = try #require(symbols("kotlinx.io.bytestring.ByteString").first {
            sema.symbols.symbol($0)?.kind == .function && sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        })
        #expect(annotated(emptyFactory, "JsName"))
        #expect(sema.symbols.annotations(for: emptyFactory).contains { $0.arguments.joined().contains("EmptyByteString") })

        let getter = try #require(symbols("kotlinx.io.bytestring.ByteString.getBackingArrayReference").first)
        #expect(sema.symbols.symbol(getter)?.visibility == .internal)
        #expect(annotated(getter, "PublishedApi"))
        let appendable = try #require(symbols("kotlinx.io.bytestring.encodeToAppendable").first)
        #expect(annotated(appendable, "IgnorableReturnValue"))

        let marker = try #require(symbols("kotlinx.io.bytestring.unsafe.UnsafeByteStringApi").first)
        #expect(annotated(marker, "MustBeDocumented"))
        let annotations = sema.symbols.annotations(for: marker)
        #expect(annotations.contains { $0.annotationFQName.hasSuffix("Retention") && $0.arguments.joined().contains("BINARY") })
        #expect(annotations.contains { $0.annotationFQName.hasSuffix("RequiresOptIn") && $0.arguments.joined().contains("ERROR") })
        let requiresOptIn = try #require(annotations.first { $0.annotationFQName.hasSuffix("RequiresOptIn") })
        let message = try #require(requiresOptIn.arguments.first { $0.hasPrefix("message=") })
        #expect(message.dropFirst("message=".count).replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "+", with: "") == unsafeWarning)
    }

    @Test(arguments: [true, false])
    func unsignedFactoryAndDirectUnsafeCallbackKeepClientContracts(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = try makeContractContext("""
        import kotlinx.io.bytestring.ByteString
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations
        fun use(first: UByte, second: UByte) {
            val bytes = ByteString(first, second)
            UnsafeByteStringOperations.withByteArrayUnsafe(bytes) { println(it.size) }
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        try checkContractProvenance(ctx, library: allowDefaultStdlibLibrary)
        let diagnostics = ctx.diagnostics.diagnostics
        let optIn = diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("UnsafeByteStringApi") }
        #expect(!optIn.isEmpty)
        #expect(optIn.allSatisfy { $0.severity == .error })
        #expect(optIn.allSatisfy { $0.message.contains(unsafeWarning) })
        #expect(!diagnostics.contains { $0.message.contains("ExperimentalUnsignedTypes") })
        #expect(diagnostics.filter { $0.severity == .error }.count == optIn.count,
                "Only the direct unsafe callback must require opt-in: \(diagnostics)")
        let sema = try #require(ctx.sema)
        let factories = sema.symbols.lookupAll(fqName: "kotlinx.io.bytestring.ByteString"
            .split(separator: ".").map { ctx.interner.intern(String($0)) })
        let unsigned = factories.filter { id in
            guard let signature = sema.symbols.functionSignature(for: id) else { return false }
            return signature.valueParameterIsVararg == [true] && signature.parameterTypes == [sema.types.ubyteType]
        }
        #expect(unsigned.count == 1, "Unsigned vararg keeps its distinct scalar element type")
    }
}
#endif
