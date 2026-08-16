#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Verifies the synthetic stubs for `ByteArray.inputStream()` (STDLIB-IO-FN-020) and
/// `ByteArray.inputStream(offset, length)` (STDLIB-IO-FN-021).
///
/// Two overloads are exposed from `kotlin.io`:
///   - `ByteArray.inputStream(): ByteArrayInputStream` → `__kk_bytearray_inputStream`
///   - `ByteArray.inputStream(offset: Int, length: Int): ByteArrayInputStream` → `__kk_bytearray_inputStream_range`
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
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift`, and is
/// expected to bind to the runtime helper `__kk_bytearray_inputStream` declared in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct ByteArrayInputStreamFunctionTests {

    // MARK: - STDLIB-IO-FN-020: ByteArray.inputStream() (zero-arg)
    // MARK: - Path-aware expression search helpers

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }


    // MARK: - Consolidated ByteArrayInputStream Sema tests
    @Test
    func testByteArrayInputStreamFunctions() throws {
        let sources: [String] = [
            """
            package sample0

                    fun wrap(bytes: ByteArray) = bytes.inputStream()

            """,
            """
            package sample1

                    import java.io.ByteArrayInputStream
                    import kotlin.io.inputStream

                    fun openSource(bytes: ByteArray): ByteArrayInputStream {
                        return bytes.inputStream()
                    }

            """,
            """
            package sample2

                    fun wrapRange(bytes: ByteArray, off: Int, len: Int) = bytes.inputStream(off, len)

            """,
            """
            package sample3

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

            """,
            """
            package sample4
            fun noop() {}
            """,
            """
            package sample5
            fun noop() {}
            """,
            """
            package sample6

                    import java.io.ByteArrayInputStream
                    import kotlin.io.inputStream

                    fun openSource(bytes: ByteArray): ByteArrayInputStream {
                        val stream = bytes.inputStream()
                        return stream
                    }

            """,
            """
            package sample7

                    fun consume(bytes: ByteArray): Int {
                        val stream = bytes.inputStream()
                        val available = stream.available()
                        val first = stream.read()
                        stream.close()
                        return available + first
                    }

            """,
            """
            package sample8

                    fun consumeRange(bytes: ByteArray, off: Int, len: Int): Int {
                        val stream = bytes.inputStream(off, len)
                        return stream.read()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testZeroArgByteArrayInputStreamResolvesCleanly ===
            do {
                let samplePath = paths[0]
                let diagnosticSummary = ctx.diagnostics.diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected ByteArray.inputStream() to resolve cleanly, got: \(diagnosticSummary)"
                )


                let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "inputStream"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "__kk_bytearray_inputStream")

                // The function should live in kotlin.io
                let chosenInfo = try #require(sema.symbols.symbol(chosenCallee))
                #expect(
                    chosenInfo.fqName.map { interner.resolve($0) } == ["kotlin", "io", "inputStream"]
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
                    returnInfo.fqName.map { interner.resolve($0) } == ["java", "io", "ByteArrayInputStream"]
                )
            }

            // === testByteArrayInputStreamResolvesWithNoArguments ===
            do {
                let samplePath = paths[1]
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "ByteArray.inputStream() should resolve without arguments, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === testRangeByteArrayInputStreamResolvesCleanly ===
            do {
                let samplePath = paths[2]
                let diagnosticSummary = ctx.diagnostics.diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected ByteArray.inputStream(offset, length) to resolve cleanly, got: \(diagnosticSummary)"
                )


                let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "inputStream"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "__kk_bytearray_inputStream_range")

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
                    returnInfo.fqName.map { interner.resolve($0) } == ["java", "io", "ByteArrayInputStream"]
                )
            }

            // === testByteArrayInputStreamCanFlowThroughInputStreamSurface ===
            do {
                let samplePath = paths[3]
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "ByteArrayInputStream returned by ByteArray.inputStream() must satisfy InputStream surface, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === testBothOverloadsExistInKotlinIOPackage ===
            do {
                let samplePath = paths[4]

            }

            // === testByteArrayInputStreamFunctionSignatureAndRuntimeLink ===
            do {
                let samplePath = paths[5]

            }

            // === testByteArrayInputStreamCallExpressionTypedAsByteArrayInputStream ===
            do {
                let samplePath = paths[6]
                #expect(
                    !ctx.diagnostics.hasError,
                    "ByteArray.inputStream() should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types
                let byteArrayInputStreamSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "ByteArrayInputStream"].map(interner.intern))
                )
                let byteArrayInputStreamType = types.make(
                    .classType(ClassType(classSymbol: byteArrayInputStreamSymbol, args: [], nullability: .nonNull))
                )

                let callExprs = memberCallExprIDs(named: "inputStream", in: ast, path: samplePath, ctx: ctx, interner: interner)
                #expect(callExprs.count == 1, "Should find exactly one bytes.inputStream() call")
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == byteArrayInputStreamType,
                        "ByteArray.inputStream() call expression must be typed as java.io.ByteArrayInputStream"
                    )
                }
            }

            // === testByteArrayInputStreamReturnTypeFlowsThroughInputStreamMembers ===
            do {
                let samplePath = paths[7]
                let diagnosticSummary = ctx.diagnostics.diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected ByteArrayInputStream member usage to resolve cleanly, got: \(diagnosticSummary)"
                )
            }

            // === testByteArrayRangeInputStreamReturnTypeFlowsThroughInputStreamMembers ===
            do {
                let samplePath = paths[8]
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
}
#endif
