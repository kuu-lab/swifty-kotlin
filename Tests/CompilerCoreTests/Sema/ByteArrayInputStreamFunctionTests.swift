#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Verifies the synthetic stubs for `ByteArray.inputStream()` (STDLIB-IO-FN-020) and
/// `ByteArray.inputStream(offset, length)` (STDLIB-IO-FN-021).
///
/// Two overloads are exposed from `kotlin.io`:
///   - `ByteArray.inputStream(): ByteArrayInputStream` → `kk_bytearray_inputStream`
///   - `ByteArray.inputStream(offset: Int, length: Int): ByteArrayInputStream` → `kk_bytearray_inputStream_range`
///
/// Both return `java.io.ByteArrayInputStream`, which is registered as an
/// `InputStream` subtype so that resource-management surfaces (`.use {}`) work
/// out of the box.
///
/// STDLIB-IO-FN-020: Validates that `kotlin.io.ByteArray.inputStream(): ByteArrayInputStream`
/// extension resolves through Sema for plain `kotlin.ByteArray` receivers and yields a
/// `java.io.ByteArrayInputStream` value that is also usable through the
/// `java.io.InputStream` surface (close / read / use {} / etc.).
///
/// The extension is wired through the synthetic File IO stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift`, and is
/// expected to bind to the runtime helper `kk_bytearray_inputStream` declared in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct ByteArrayInputStreamFunctionTests {
    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - STDLIB-IO-FN-020: ByteArray.inputStream() (zero-arg)

    @Test func testZeroArgByteArrayInputStreamResolvesCleanly() throws {
        let source = """
        fun wrap(bytes: ByteArray) = bytes.inputStream()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected ByteArray.inputStream() to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "inputStream"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_bytearray_inputStream")

            // The function should live in kotlin.io
            let chosenInfo = try #require(sema.symbols.symbol(chosenCallee))
            #expect(
                chosenInfo.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "io", "inputStream"]
            )

            // The overload must have zero value parameters
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(signature.parameterTypes.isEmpty)

            // Return type must be java.io.ByteArrayInputStream
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected ByteArray.inputStream() to return a class type")
                return
            }
            let returnInfo = try #require(sema.symbols.symbol(returnClassType.classSymbol))
            #expect(
                returnInfo.fqName.map { ctx.interner.resolve($0) } == ["java", "io", "ByteArrayInputStream"]
            )
        }
    }

    @Test func testByteArrayInputStreamResolvesWithNoArguments() throws {
        let source = """
        import java.io.ByteArrayInputStream
        import kotlin.io.inputStream

        fun openSource(bytes: ByteArray): ByteArrayInputStream {
            return bytes.inputStream()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "ByteArray.inputStream() should resolve without arguments, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - STDLIB-IO-FN-021: ByteArray.inputStream(offset, length) (range)

    @Test func testRangeByteArrayInputStreamResolvesCleanly() throws {
        let source = """
        fun wrapRange(bytes: ByteArray, off: Int, len: Int) = bytes.inputStream(off, len)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected ByteArray.inputStream(offset, length) to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "inputStream"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_bytearray_inputStream_range")

            // The overload must have two Int parameters: offset and length
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(signature.parameterTypes.count == 2)
            #expect(signature.parameterTypes[0] == sema.types.intType)
            #expect(signature.parameterTypes[1] == sema.types.intType)

            // Return type must be java.io.ByteArrayInputStream
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected ByteArray.inputStream(offset, length) to return a class type")
                return
            }
            let returnInfo = try #require(sema.symbols.symbol(returnClassType.classSymbol))
            #expect(
                returnInfo.fqName.map { ctx.interner.resolve($0) } == ["java", "io", "ByteArrayInputStream"]
            )
        }
    }

    @Test func testByteArrayInputStreamCanFlowThroughInputStreamSurface() throws {
        // ByteArrayInputStream extends InputStream, so the returned value can be
        // bound to an InputStream variable and used through Closeable/.use {} as
        // well as read()/available()/close() surface methods.
        let source = """
        import java.io.ByteArrayInputStream
        import java.io.InputStream
        import kotlin.io.inputStream

        fun consume(bytes: ByteArray): Int {
            val stream: ByteArrayInputStream = bytes.inputStream()
            val byte: Int = stream.read()
            val remaining: Int = stream.available()
            stream.close()
            return byte + remaining
        }

        fun useViaCloseable(bytes: ByteArray): Int {
            val raw: InputStream = bytes.inputStream()
            return raw.use { stream ->
                stream.read()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "ByteArrayInputStream returned by ByteArray.inputStream() must satisfy InputStream surface, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testBothOverloadsExistInKotlinIOPackage() throws {
        // Direct symbol lookup to verify both inputStream stubs live in kotlin.io.
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let fqName = ["kotlin", "io", "inputStream"].map { interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fqName)

            // Expect at least the two ByteArray overloads (there may be others from File/Path)
            let byteArrayFQName = ["kotlin", "ByteArray"].map { interner.intern($0) }
            guard let byteArraySymbol = sema.symbols.lookup(fqName: byteArrayFQName) else {
                Issue.record("kotlin.ByteArray symbol not found")
                return
            }
            let byteArrayType = sema.types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))

            let byteArrayOverloads = symbols.filter { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == byteArrayType
            }
            #expect(
                byteArrayOverloads.count >= 2,
                "Expected at least two ByteArray.inputStream overloads in kotlin.io"
            )

            let externalLinks = Set(byteArrayOverloads.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(
                externalLinks.contains("kk_bytearray_inputStream"),
                "Zero-arg overload kk_bytearray_inputStream not found"
            )
            #expect(
                externalLinks.contains("kk_bytearray_inputStream_range"),
                "Range overload kk_bytearray_inputStream_range not found"
            )
        }
    }

    @Test func testByteArrayInputStreamFunctionSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let byteArraySymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "ByteArray"].map(interner.intern))
            )
            let byteArrayType = types.make(
                .classType(ClassType(classSymbol: byteArraySymbol, args: [], nullability: .nonNull))
            )
            let byteArrayInputStreamSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "ByteArrayInputStream"].map(interner.intern))
            )
            let byteArrayInputStreamType = types.make(
                .classType(ClassType(classSymbol: byteArrayInputStreamSymbol, args: [], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "inputStream"].map(interner.intern)
            )
            let inputStream = try #require(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == byteArrayType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == byteArrayInputStreamType
            }, "Expected a kotlin.io.inputStream extension with ByteArray receiver and ByteArrayInputStream return")

            #expect(
                symbols.externalLinkName(for: inputStream) == "kk_bytearray_inputStream",
                "ByteArray.inputStream should bind to runtime helper kk_bytearray_inputStream"
            )

            let signature = try #require(symbols.functionSignature(for: inputStream))
            #expect(signature.receiverType == byteArrayType)
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.returnType == byteArrayInputStreamType)
            #expect(!signature.isSuspend)
        }
    }

    @Test func testByteArrayInputStreamCallExpressionTypedAsByteArrayInputStream() throws {
        let source = """
        import java.io.ByteArrayInputStream
        import kotlin.io.inputStream

        fun openSource(bytes: ByteArray): ByteArrayInputStream {
            val stream = bytes.inputStream()
            return stream
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "ByteArray.inputStream() should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let byteArrayInputStreamSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "ByteArrayInputStream"].map(interner.intern))
            )
            let byteArrayInputStreamType = types.make(
                .classType(ClassType(classSymbol: byteArrayInputStreamSymbol, args: [], nullability: .nonNull))
            )

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "inputStream", in: ast, interner: interner)
            #expect(callExprs.count == 1, "Should find exactly one bytes.inputStream() call")
            for callExpr in callExprs {
                #expect(
                    sema.bindings.exprTypes[callExpr] == byteArrayInputStreamType,
                    "ByteArray.inputStream() call expression must be typed as java.io.ByteArrayInputStream"
                )
            }
        }
    }

    @Test func testByteArrayInputStreamReturnTypeFlowsThroughInputStreamMembers() throws {
        // ByteArrayInputStream extends InputStream, so its member surfaces
        // (.read(), .close(), .available()) must resolve cleanly.
        let source = """
        fun consume(bytes: ByteArray): Int {
            val stream = bytes.inputStream()
            val available = stream.available()
            val first = stream.read()
            stream.close()
            return available + first
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected ByteArrayInputStream member usage to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    @Test func testByteArrayRangeInputStreamReturnTypeFlowsThroughInputStreamMembers() throws {
        // ByteArrayInputStream(offset, length) should also provide InputStream members.
        let source = """
        fun consumeRange(bytes: ByteArray, off: Int, len: Int): Int {
            val stream = bytes.inputStream(off, len)
            return stream.read()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected ByteArrayInputStream(range) member usage to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
#endif
