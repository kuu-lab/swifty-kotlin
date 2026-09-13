#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

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

    @Test func testBufferedInputStreamReadBytesResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected BufferedInputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testInputStreamReadBytesInsideUseBlock() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected InputStream.use { it.readBytes() } to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    ///   - the external link name resolves to `__kk_input_stream_readAllBytes`
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

    /// The runtime helper `__kk_input_stream_readAllBytes` must be declared in
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
