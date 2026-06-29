#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-FN-033: Validates that `kotlin.io.Reader.readText()` resolves
/// through Sema as an extension function on `java.io.Reader`. The synthetic
/// `Reader` supertype lets concrete reader values (currently `BufferedReader`
/// instances produced by `File.bufferedReader()`) participate in the call
/// without explicit upcasting.
///
/// Verifies:
///   1. The synthetic symbol is registered with the correct extension
///      receiver, parameter list, return type, and runtime link name
///      (`kk_reader_readText`).
///   2. The function resolves end-to-end when invoked on a `BufferedReader`
///      value, including the common `File("...").bufferedReader().readText()`
///      chain and inside a `use { }` block.
@Suite
struct ReaderReadTextFunctionTests {

    // MARK: - Symbol surface

    @Test func testReaderReadTextFunctionIsRegisteredOnReaderReceiver() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "Sema should succeed on a trivial program: " +
                    "\(ctx.diagnostics.diagnostics.map(\.message))")
            )
            let sema = try #require(ctx.sema)

            let readerFQ = ["java", "io", "Reader"].map { ctx.interner.intern($0) }
            let readerSymbol = try #require(
                sema.symbols.lookup(fqName: readerFQ),
                "java.io.Reader synthetic class should be registered"
            )
            let readerType = sema.types.make(.classType(ClassType(
                classSymbol: readerSymbol, args: [], nullability: .nonNull
            )))

            let readTextFQ = ["kotlin", "io", "readText"].map { ctx.interner.intern($0) }
            let readTextSymbol = try #require(
                sema.symbols.lookupAll(fqName: readTextFQ).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == readerType
                        && signature.parameterTypes.isEmpty
                },
                "kotlin.io.Reader.readText() extension should be registered"
            )

            let signature = try #require(sema.symbols.functionSignature(for: readTextSymbol))
            #expect(
                signature.returnType == sema.types.stringType,
                "Reader.readText() must return non-null String"
            )
            #expect(
                !(signature.isSuspend),
                "Reader.readText() is not a suspend function"
            )
            #expect(
                sema.symbols.externalLinkName(for: readTextSymbol) == "kk_reader_readText",
                "Reader.readText() must lower to kk_reader_readText runtime entry"
            )
        }
    }

    // MARK: - BufferedReader inherits from Reader

    @Test func testBufferedReaderIsRegisteredAsReaderSubtype() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            let readerFQ = ["java", "io", "Reader"].map { ctx.interner.intern($0) }
            let bufferedReaderFQ = ["java", "io", "BufferedReader"].map { ctx.interner.intern($0) }
            let readerSymbol = try #require(sema.symbols.lookup(fqName: readerFQ))
            let bufferedReaderSymbol = try #require(sema.symbols.lookup(fqName: bufferedReaderFQ))
            let directSupertypes = sema.symbols.directSupertypes(for: bufferedReaderSymbol)
            #expect(
                directSupertypes.contains(readerSymbol),
                Comment(rawValue: "BufferedReader must list Reader among its direct supertypes; got: \(directSupertypes)")
            )
        }
    }

    // MARK: - Resolves end-to-end on BufferedReader chain

    @Test func testReaderReadTextResolvesOnBufferedReaderChain() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(): String {
            return File("/dev/null").bufferedReader().readText()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "File(...).bufferedReader().readText() should type-check, got: " +
                "\(errors.map { "\($0.code): \($0.message)" })")
        )
    }

    @Test func testReaderReadTextReturnsStringInVariableBinding() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAll(file: File): String {
            val reader = file.bufferedReader()
            val text: String = reader.readText()
            reader.close()
            return text
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Binding `val text: String = reader.readText()` should compile, got: " +
                "\(errors.map { "\($0.code): \($0.message)" })")
        )
    }

    // MARK: - Works inside Closeable.use { } block

    @Test func testReaderReadTextWorksInsideUseBlock() throws {
        let ctx = makeContextFromSource("""
        import java.io.File

        fun loadAllSafely(file: File): String {
            return file.bufferedReader().use { reader ->
                reader.readText()
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Reader.readText() inside a use { } block should compile, got: " +
                "\(errors.map { "\($0.code): \($0.message)" })")
        )
    }
}
#endif
