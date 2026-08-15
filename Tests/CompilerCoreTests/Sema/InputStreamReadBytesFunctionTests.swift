#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

/// STDLIB-IO-FN-029: Validates that `InputStream.readBytes()` resolves through
/// Sema for the `java.io.InputStream` receiver and produces a `ByteArray`
/// value (modelled in the runtime as `List<Int>`).  The synthetic stub is
/// registered in `HeaderHelpers+SyntheticTODOAndIOStubs.swift` and binds to the
/// runtime helper `__kk_input_stream_readAllBytes` declared in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
///
/// The receiver is NOT closed by `readBytes()` — callers are expected to wrap
/// the call in `.use { it.readBytes() }`.  These tests pin down both the
/// stand-alone call shape and the more idiomatic `.use` pattern.
@Suite
struct InputStreamReadBytesFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import java.io.File

        fun loadAll(file: File) {
            val stream = file.inputStream()
            val result = stream.readBytes()
        }
        """,
        """
        package sample1
        import java.io.BufferedInputStream
        import java.io.File

        fun loadAll(file: File) {
            val buffered: BufferedInputStream = file.inputStream().buffered()
            val result = buffered.readBytes()
        }
        """,
        """
        package sample2
        import java.io.File

        fun loadAll(file: File) {
            val result = file.inputStream().use { stream ->
                stream.readBytes()
            }
        }
        """,
        """
        package sample3
        fun noop() {}
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    // MARK: - Basic resolution

    /// `InputStream.readBytes()` should type-check when invoked on a plain
    /// `java.io.InputStream` receiver.  The returned value must be assignable
    /// to a `ByteArray` (which the runtime models as `List<Int>`).
    @Test func testInputStreamReadBytesResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected InputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// `BufferedInputStream` is a subtype of `InputStream`, so the receiver
    /// inheritance check should also let `readBytes()` resolve when the static
    /// receiver type is a buffered stream.  This exercises the inheritance
    /// path through the synthetic stub registry.
    @Test func testBufferedInputStreamReadBytesResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected BufferedInputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// The idiomatic Kotlin usage wraps the call in `.use { }`, which both
    /// drains the stream and closes the resource.  Sema must resolve the
    /// `readBytes()` invocation inside a closure body when the receiver flows
    /// through the synthetic `Closeable.use` extension.
    @Test func testInputStreamReadBytesInsideUseBlock() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected InputStream.use { it.readBytes() } to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Signature / runtime link

    /// Pin down the symbol-level invariants we expect from the synthetic
    /// `InputStream.readBytes()` stub:
    ///   - the symbol is registered under `java.io.InputStream.readBytes`
    ///   - the receiver type is `java.io.InputStream`
    ///   - there are no value parameters
    ///   - the return type is `kotlin.collections.List<Int>` (the runtime's
    ///     ByteArray representation)
    ///   - the external link name resolves to `__kk_input_stream_readAllBytes`
    ///
    /// Pinning these here guards against accidental renames or signature
    /// drift that would silently break the lowering pipeline.
    @Test func testInputStreamReadBytesSignatureAndRuntimeLink() throws {
        let ctx = try sharedCtx()
        let interner = ctx.interner
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let types = sema.types

        let inputStreamSymbol = try #require(
            symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
        )
        let inputStreamType = types.make(
            .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
        )
        let listSymbol = try #require(
            symbols.lookup(fqName: ["kotlin", "collections", "List"].map(interner.intern))
        )
        let listOfIntType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.intType)],
            nullability: .nonNull
        )))

        let candidates = symbols.lookupAll(
            fqName: ["java", "io", "InputStream", "readBytes"].map(interner.intern)
        )
        let readBytes = try #require(candidates.first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == inputStreamType
                && signature.parameterTypes.isEmpty
        })

        #expect(
            symbols.externalLinkName(for: readBytes) == "__kk_input_stream_readAllBytes",
            "InputStream.readBytes should bind to runtime helper __kk_input_stream_readAllBytes"
        )

        let signature = try #require(symbols.functionSignature(for: readBytes))
        #expect(signature.returnType == listOfIntType,
                       "InputStream.readBytes() must return ByteArray (List<Int>)")
        #expect(signature.receiverType == inputStreamType)
        #expect(signature.valueParameterIsVararg.allSatisfy { !$0 })
        #expect(signature.valueParameterHasDefaultValues.allSatisfy { !$0 })
    }

    // MARK: - Runtime ABI registration

    /// The runtime helper `__kk_input_stream_readAllBytes` must be declared in
    /// the FileIO ABI spec with the (streamRaw, outThrown) signature so the
    /// codegen pass can emit the correct extern declaration.
    @Test func testRuntimeABISpecRegistersReadAllBytes() throws {
        let spec = RuntimeABISpec.fileIOFunctions.first { $0.name == "__kk_input_stream_readAllBytes" }
        let unwrapped = try #require(
            spec,
            "__kk_input_stream_readAllBytes must be registered in RuntimeABISpec+FileIO.swift"
        )
        #expect(unwrapped.parameters.count == 2)
        #expect(unwrapped.parameters[0].name == "streamRaw")
        #expect(unwrapped.parameters[0].type == .intptr)
        #expect(unwrapped.parameters[1].name == "outThrown")
        #expect(unwrapped.parameters[1].type == .nullableIntptrPointer)
        #expect(unwrapped.returnType == .intptr)
        #expect(unwrapped.section == "FileIO")
    }
}
#endif
