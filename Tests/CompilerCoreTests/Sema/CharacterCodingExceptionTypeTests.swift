#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-TYPE-002: Validates that `kotlin.text.CharacterCodingException`
/// is registered as a synthetic class in the `kotlin.text` package with
/// `Exception` as a direct supertype and exposes the two stdlib constructors
/// (`()` and `(message: String?)`). See
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticExceptionStubs.swift`
/// for the registration site and the constructors are routed to the runtime
/// link `__kk_throwable_new`.
@Suite
struct CharacterCodingExceptionTypeTests {


    // MARK: - Symbol surface

    // MARK: - Constructors

    // MARK: - Source resolution

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
            // testCharacterCodingExceptionIsRegisteredAsClassInKotlinTextPackage
            """
            package sample0
            fun noop() {}
            """,
            // testCharacterCodingExceptionHasExceptionDirectSupertype
            """
            package sample1
            fun noop() {}
            """,
            // testCharacterCodingExceptionIsAssignableToExceptionAndThrowable
            """
            package sample2
            fun noop() {}
            """,
            // testCharacterCodingExceptionExposesNoArgAndMessageConstructors
            """
            package sample3
            fun noop() {}
            """,
            // testCharacterCodingExceptionTypeChecksThroughImport
            """
            package sample4

                    import kotlin.text.CharacterCodingException

                    fun throwImported(): Nothing = throw CharacterCodingException()
                    fun throwImportedWithMessage(): Nothing = throw CharacterCodingException("bad input")

                    fun catchAsCharacterCoding(): String =
                        try { throw CharacterCodingException("decode failed") }
                        catch (e: CharacterCodingException) { e.message ?: "none" }

                    fun catchAsException(): String =
                        try { throw CharacterCodingException("encode failed") }
                        catch (e: Exception) { e.message ?: "none" }

                    fun catchAsThrowable(): String =
                        try { throw CharacterCodingException("io failed") }
                        catch (t: Throwable) { t.message ?: "none" }

            """,
            // testCharacterCodingExceptionAcceptsNullMessageArgument
            """
            package sample5

                    import kotlin.text.CharacterCodingException

                    fun nullable(message: String?): Exception = CharacterCodingException(message)
                    fun explicitNull(): Exception = CharacterCodingException(null)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCharacterCodingExceptionIsRegisteredAsClassInKotlinTextPackage ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let fqName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.text.CharacterCodingException to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .class)

            }

            // === testCharacterCodingExceptionHasExceptionDirectSupertype ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let exceptionFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
                let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))

                let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
                let rootExceptionSymbol = try #require(sema.symbols.lookup(fqName: rootExceptionFQName))

                #expect(
                    sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol),
                    "CharacterCodingException should directly inherit from kotlin.Exception"
                )

            }

            // === testCharacterCodingExceptionIsAssignableToExceptionAndThrowable ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let characterCodingFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
                let characterCodingSymbol = try #require(sema.symbols.lookup(fqName: characterCodingFQName))
                let characterCodingType = sema.types.make(.classType(ClassType(
                    classSymbol: characterCodingSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let exceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
                let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
                let exceptionType = sema.types.make(.classType(ClassType(
                    classSymbol: exceptionSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
                let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
                let throwableType = sema.types.make(.classType(ClassType(
                    classSymbol: throwableSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                #expect(
                    sema.types.isSubtype(characterCodingType, exceptionType),
                    "CharacterCodingException should be a subtype of kotlin.Exception"
                )
                #expect(
                    sema.types.isSubtype(characterCodingType, throwableType),
                    "CharacterCodingException should be a (transitive) subtype of kotlin.Throwable"
                )

            }

            // === testCharacterCodingExceptionExposesNoArgAndMessageConstructors ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let exceptionFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
                let exceptionSymbol = try #require(sema.symbols.lookup(fqName: exceptionFQName))
                let exceptionType = sema.types.make(.classType(ClassType(
                    classSymbol: exceptionSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let nullableStringType = sema.types.makeNullable(sema.types.stringType)
                let constructorFQName = exceptionFQName + [interner.intern("<init>")]
                let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
                    sema.symbols.symbol($0)?.kind == .constructor
                }

                #expect(
                    constructors.count == 2,
                    "CharacterCodingException should expose exactly the no-arg and single-message constructors"
                )

                let expected: [([TypeID], String)] = [
                    ([], "__kk_throwable_new"),
                    ([nullableStringType], "__kk_throwable_new"),
                ]
                for (parameterTypes, externalLinkName) in expected {
                    let constructor = try #require(
                        constructors.first {
                            sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
                        },
                        "Missing CharacterCodingException constructor with parameters \(parameterTypes)"
                    )
                    #expect(
                        sema.symbols.functionSignature(for: constructor)?.returnType == exceptionType,
                        "Constructor should return CharacterCodingException"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: constructor) == externalLinkName,
                        "Constructor with parameters \(parameterTypes) should bind to \(externalLinkName)"
                    )
                }

            }

            // === testCharacterCodingExceptionTypeChecksThroughImport ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let errors = sample4Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected CharacterCodingException to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharacterCodingExceptionAcceptsNullMessageArgument ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let errors = sample5Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected CharacterCodingException(message: String?) to accept nullable arguments, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

        }
    }

}

#endif
