#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-568 / KUU-654: String.replaceFirstChar keeps both Char and CharSequence transform overloads.
@Suite
struct StringReplaceFirstCharOverloadTests {
    private let sourcePath = "__bundled_kotlin/text/StringCaseConversion.kt"

    @Test
    func declarationsExposeBothTransformReturnTypes() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: "; ")
        #expect(
            !ctx.diagnostics.hasError,
            "diagnostics: \(diagnosticSummary)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let declarations = sema.symbols.lookupAll(
            fqName: ["kotlin", "text", "replaceFirstChar"].map(interner.intern)
        ).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID),
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  signature.receiverType == sema.types.stringType,
                  signature.returnType == sema.types.stringType,
                  signature.parameterTypes.count == 1,
                  case .functionType = sema.types.kind(of: signature.parameterTypes[0])
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == sourcePath
        }

        #expect(declarations.count == 2, "Expected both source-backed replaceFirstChar overloads")
        let transformReturnTypes = Set(declarations.compactMap { symbolID -> TypeID? in
            guard let parameterType = sema.symbols.functionSignature(for: symbolID)?.parameterTypes.first,
                  case let .functionType(transformType) = sema.types.kind(of: parameterType)
            else {
                return nil
            }
            return transformType.returnType
        })
        #expect(transformReturnTypes == Set([sema.types.charType, charSequenceType]))
        #expect(declarations.allSatisfy { symbolID in
            sema.symbols.annotations(for: symbolID).contains {
                KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches($0.annotationFQName)
            }
        })
        #expect(declarations.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
    }

    @Test
    func callsSelectCharAndCharSequenceTransformOverloads() throws {
        let source = """
        fun uppercase(value: String): String = value.replaceFirstChar { it.uppercase() }
        fun uppercaseChar(value: String): String = value.replaceFirstChar { it.uppercaseChar() }
        fun titlecase(value: String): String = value.replaceFirstChar(Char::titlecase)
        fun lowercase(value: String): String = value.replaceFirstChar { it.lowercase() }
        fun lowercaseChar(value: String): String = value.replaceFirstChar { it.lowercaseChar() }
        fun multiChar(value: String): String = value.replaceFirstChar { "YY" }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: "; ")
        #expect(
            !ctx.diagnostics.hasError,
            "diagnostics: \(diagnosticSummary)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(ctx.interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "replaceFirstChar",
                  range.start.file == userFileID
            else {
                return nil
            }
            return exprID
        }
        let expectedTransformReturnTypes = [
            charSequenceType,
            sema.types.charType,
            charSequenceType,
            charSequenceType,
            sema.types.charType,
            charSequenceType,
        ]

        #expect(calls.count == expectedTransformReturnTypes.count, "Expected six replaceFirstChar calls")
        for (call, expectedReturnType) in zip(calls, expectedTransformReturnTypes) {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let transformParameter = try #require(signature.parameterTypes.first)
            guard case let .functionType(transformType) = sema.types.kind(of: transformParameter) else {
                Issue.record("replaceFirstChar transform should be a function type")
                continue
            }
            #expect(transformType.params == [sema.types.charType])
            #expect(transformType.returnType == expectedReturnType)
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }
    }
}
#endif
