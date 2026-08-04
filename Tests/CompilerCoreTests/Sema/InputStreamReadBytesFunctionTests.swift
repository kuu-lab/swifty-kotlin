#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

/// STDLIB-IO-FN-029: Validates that `InputStream.readBytes()` resolves through
/// Sema for the `java.io.InputStream` receiver and produces a `ByteArray`
/// value (modelled in the runtime as `List<Int>`).  The synthetic stub is
/// registered in `HeaderHelpers+SyntheticFileIOStubs.swift` and binds to the
/// runtime helper `kk_input_stream_readAllBytes` declared in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
///
/// The receiver is NOT closed by `readBytes()` — callers are expected to wrap
/// the call in `.use { it.readBytes() }`.  These tests pin down both the
/// stand-alone call shape and the more idiomatic `.use` pattern.
@Suite
struct InputStreamReadBytesFunctionTests {

    // MARK: - Basic resolution

    /// `InputStream.readBytes()` should type-check when invoked on a plain
    /// `java.io.InputStream` receiver.  The returned value must be assignable
    /// to a `ByteArray` (which the runtime models as `List<Int>`).

    /// `BufferedInputStream` is a subtype of `InputStream`, so the receiver
    /// inheritance check should also let `readBytes()` resolve when the static
    /// receiver type is a buffered stream.  This exercises the inheritance
    /// path through the synthetic stub registry.

    /// The idiomatic Kotlin usage wraps the call in `.use { }`, which both
    /// drains the stream and closes the resource.  Sema must resolve the
    /// `readBytes()` invocation inside a closure body when the receiver flows
    /// through the synthetic `Closeable.use` extension.

    // MARK: - Signature / runtime link

    /// Pin down the symbol-level invariants we expect from the synthetic
    /// `InputStream.readBytes()` stub:
    ///   - the symbol is registered under `java.io.InputStream.readBytes`
    ///   - the receiver type is `java.io.InputStream`
    ///   - there are no value parameters
    ///   - the return type is `kotlin.collections.List<Int>` (the runtime's
    ///     ByteArray representation)
    ///   - the external link name resolves to `kk_input_stream_readAllBytes`
    ///
    /// Pinning these here guards against accidental renames or signature
    /// drift that would silently break the lowering pipeline.

    // MARK: - Runtime ABI registration

    /// The runtime helper `kk_input_stream_readAllBytes` must be declared in
    /// the FileIO ABI spec with the (streamRaw, outThrown) signature so the
    /// codegen pass can emit the correct extern declaration.

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
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

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
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

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testInputStreamReadBytesResolves
            """
            package sample0

                    import java.io.File

                    fun loadAll(file: File) {
                        val stream = file.inputStream()
                        val result = stream.readBytes()
                    }

            """,
            // testBufferedInputStreamReadBytesResolves
            """
            package sample1

                    import java.io.BufferedInputStream
                    import java.io.File

                    fun loadAll(file: File) {
                        val buffered: BufferedInputStream = file.inputStream().buffered()
                        val result = buffered.readBytes()
                    }

            """,
            // testInputStreamReadBytesInsideUseBlock
            """
            package sample2

                    import java.io.File

                    fun loadAll(file: File) {
                        val result = file.inputStream().use { stream ->
                            stream.readBytes()
                        }
                    }

            """,
            // testInputStreamReadBytesSignatureAndRuntimeLink
            """
            package sample3
            fun noop() {}
            """,
            // testRuntimeABISpecRegistersReadAllBytes
            """
            package sample4
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testInputStreamReadBytesResolves ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected InputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testBufferedInputStreamReadBytesResolves ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected BufferedInputStream.readBytes() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testInputStreamReadBytesInsideUseBlock ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected InputStream.use { it.readBytes() } to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testInputStreamReadBytesSignatureAndRuntimeLink ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

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
                    symbols.externalLinkName(for: readBytes) == "kk_input_stream_readAllBytes",
                    "InputStream.readBytes should bind to runtime helper kk_input_stream_readAllBytes"
                )

                let signature = try #require(symbols.functionSignature(for: readBytes))
                #expect(signature.returnType == listOfIntType,
                               "InputStream.readBytes() must return ByteArray (List<Int>)")
                #expect(signature.receiverType == inputStreamType)
                #expect(signature.valueParameterIsVararg.allSatisfy { !$0 })
                #expect(signature.valueParameterHasDefaultValues.allSatisfy { !$0 })

            }

            // === testRuntimeABISpecRegistersReadAllBytes ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let spec = RuntimeABISpec.fileIOFunctions.first { $0.name == "kk_input_stream_readAllBytes" }
                let unwrapped = try #require(
                    spec,
                    "kk_input_stream_readAllBytes must be registered in RuntimeABISpec+FileIO.swift"
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
    }

}

#endif
