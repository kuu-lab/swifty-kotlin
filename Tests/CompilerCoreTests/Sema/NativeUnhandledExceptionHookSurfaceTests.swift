#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeUnhandledExceptionHookSurfaceTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func throwableType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        return sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func hookType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let throwable = try throwableType(sema: sema, interner: interner)
        return sema.types.make(.functionType(FunctionType(
            params: [throwable],
            returnType: sema.types.unitType
        )))
    }

    private func nativeSymbol(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: ["kotlin", "native", name].map { interner.intern($0) })
    }

    @Test
    func testReportUnhandledExceptionHookTypeAliasIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let alias = try #require(nativeSymbol("ReportUnhandledExceptionHook", sema: sema, interner: interner))

        #expect(sema.symbols.symbol(alias)?.kind == .typeAlias)
        #expect(sema.symbols.typeAliasUnderlyingType(for: alias) == (try hookType(sema: sema, interner: interner)))
        #expect(
            sema.symbols.annotations(for: alias).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            }
        )
    }

    @Test
    func testUnhandledExceptionHookFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let throwable = try throwableType(sema: sema, interner: interner)
        let hook = try hookType(sema: sema, interner: interner)
        let nullableHook = sema.types.makeNullable(hook)

        let expectations: [(String, [TypeID], TypeID, String, Bool)] = [
            ("getUnhandledExceptionHook", [], nullableHook, "kk_native_getUnhandledExceptionHook", false),
            ("setUnhandledExceptionHook", [nullableHook], sema.types.unitType, "kk_native_setUnhandledExceptionHook", false),
            ("processUnhandledException", [throwable], sema.types.unitType, "kk_native_processUnhandledException", true),
            ("terminateWithUnhandledException", [throwable], sema.types.nothingType, "kk_native_terminateWithUnhandledException", false),
        ]

        for (name, params, returnType, externalLinkName, canThrow) in expectations {
            let symbol = try #require(nativeSymbol(name, sema: sema, interner: interner), Comment(rawValue: name))
            let signature = try #require(sema.symbols.functionSignature(for: symbol), Comment(rawValue: name))
            #expect(signature.receiverType == nil, Comment(rawValue: name))
            #expect(signature.parameterTypes == params, Comment(rawValue: name))
            #expect(signature.returnType == returnType, Comment(rawValue: name))
            #expect(signature.canThrow == canThrow, Comment(rawValue: name))
            #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, Comment(rawValue: name))
            #expect(
                sema.symbols.annotations(for: symbol).contains {
                    $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                },
                "\(name) must carry ExperimentalNativeApi metadata"
            )
        }
    }

    @Test
    func testUnhandledExceptionHooksResolveInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.ReportUnhandledExceptionHook
        import kotlin.native.getUnhandledExceptionHook
        import kotlin.native.setUnhandledExceptionHook
        import kotlin.native.processUnhandledException
        import kotlin.native.terminateWithUnhandledException

        fun probe(throwable: Throwable) {
            val hook: ReportUnhandledExceptionHook? = getUnhandledExceptionHook()
            setUnhandledExceptionHook(hook)
            processUnhandledException(throwable)
        }

        fun die(throwable: Throwable): Nothing = terminateWithUnhandledException(throwable)
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.isEmpty, "Expected unhandled exception hooks to resolve without errors, got \(errors)")
    }
}
#endif
