#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ContextHelperSyntheticStubTests {
    @Test func testContextHelperIsRegisteredWithContextFunctionBlock() throws {
        let (sema, interner) = try makeSema()
        let contextSymbol = try #require(lookupSymbol(["kotlin", "context"], sema: sema, interner: interner))
        let symbol = try #require(sema.symbols.symbol(contextSymbol))
        let signature = try #require(sema.symbols.functionSignature(for: contextSymbol))

        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.flags.contains(.inlineFunction))
        #expect(signature.parameterTypes.count == 2)
        #expect(signature.typeParameterSymbols.count == 2)
        #expect(signature.returnType == typeParamType(signature.typeParameterSymbols[1], sema: sema))

        let contextType = typeParamType(signature.typeParameterSymbols[0], sema: sema)
        #expect(signature.parameterTypes[0] == contextType)
        guard case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes[1]) else {
            Issue.record("context block parameter should be a function type")
            return
        }
        #expect(blockType.contextReceivers == [contextType])
        #expect(blockType.params.isEmpty)
        #expect(blockType.returnType == signature.returnType)
    }

    @Test func testContextHelperRegistersOverloadsThroughAritySix() throws {
        let (sema, interner) = try makeSema()
        let contextSymbols = sema.symbols.lookupAll(fqName: ["kotlin", "context"].map { interner.intern($0) })
        let arities = Set(contextSymbols.compactMap { symbolID -> Int? in
            guard let signature = sema.symbols.functionSignature(for: symbolID),
                  case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes.last ?? .invalid),
                  blockType.params.isEmpty
            else {
                return nil
            }
            return blockType.contextReceivers.count
        })

        #expect(arities == Set(1...6))
    }

    @Test func testContextOfHelperIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let contextOfSymbol = try #require(lookupSymbol(["kotlin", "contextOf"], sema: sema, interner: interner))
        let symbol = try #require(sema.symbols.symbol(contextOfSymbol))
        let signature = try #require(sema.symbols.functionSignature(for: contextOfSymbol))

        #expect(symbol.flags.contains(.synthetic))
        #expect(symbol.flags.contains(.inlineFunction))
        #expect(signature.parameterTypes == [])
        #expect(signature.typeParameterSymbols.count == 1)
        #expect(signature.returnType == typeParamType(signature.typeParameterSymbols[0], sema: sema))
        #expect(sema.symbols.annotations(for: contextOfSymbol).contains { annotation in
            annotation.annotationFQName == "kotlin.ExperimentalContextParameters"
        })
    }

    @Test func testContextHelperRequiresExperimentalContextParametersOptIn() {
        let source = """
        fun caller(): Int = context(1) { 2 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        #expect(diagnostics.count == 1, "Expected context helper to require opt-in, got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.first?.message.contains("ExperimentalContextParameters") == true)
    }

    @Test func testContextHelperAcceptsOptInAndInfersBlockReturnType() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): String = context(1) { "ok" }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty, "Expected @OptIn to suppress context helper diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let callerSymbol = try #require(lookupSymbol(["caller"], sema: sema, interner: interner))
        let signature = try #require(sema.symbols.functionSignature(for: callerSymbol))
        #expect(signature.returnType == sema.types.stringType)
    }

    @Test func testContextOfResolvesInsideContextHelperBlock() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): String = context("ok") { contextOf<String>() }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty, "Expected @OptIn to suppress contextOf diagnostic, got: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-CTX-001", in: ctx).isEmpty, "Expected contextOf<String>() to find the String context receiver, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let callerSymbol = try #require(lookupSymbol(["caller"], sema: sema, interner: interner))
        let signature = try #require(sema.symbols.functionSignature(for: callerSymbol))
        #expect(signature.returnType == sema.types.stringType)
    }

    @Test func testContextOfReportsMissingContextReceiver() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): Int = context("ok") { contextOf<Int>() }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-CTX-001", in: ctx)
        #expect(diagnostics.count == 1, "Expected missing context receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testContextHelperSixValueOverloadInfersBlockReturnType() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): String = context(1, 2, 3, 4, 5, 6) { "ok" }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty, "Expected @OptIn to suppress context helper diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let callerSymbol = try #require(lookupSymbol(["caller"], sema: sema, interner: interner))
        let signature = try #require(sema.symbols.functionSignature(for: callerSymbol))
        #expect(signature.returnType == sema.types.stringType)
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath])
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func lookupSymbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func typeParamType(_ symbol: SymbolID, sema: SemaModule) -> TypeID {
        sema.types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
    }
}
#endif
