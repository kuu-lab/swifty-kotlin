#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerGetFunctionTests {
    @Test func testCPointerGetFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.get surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)])
            return try #require(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))

        let getFQName = cinteropPkg + [interner.intern("get")]
        let getFunctionSymbol = try #require(
            sema.symbols.lookupAll(fqName: getFQName).first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                guard let typeParam = sig.typeParameterSymbols.first else { return false }
                let typeParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParam,
                    nullability: .nonNull
                )))
                let receiverType = sema.types.make(.classType(ClassType(
                    classSymbol: cPointerSymbol,
                    args: [.invariant(typeParamType)],
                    nullability: .nonNull
                )))
                return sig.receiverType == receiverType
                    && sig.parameterTypes == [sema.types.intType]
                    && sig.returnType == typeParamType
            },
            "kotlinx.cinterop.CPointer<T>.get(index: Int): T must be registered"
        )

        let signature = try #require(sema.symbols.functionSignature(for: getFunctionSymbol))
        let typeParameter = try #require(signature.typeParameterSymbols.first)

        #expect(sema.symbols.symbol(getFunctionSymbol)?.kind == .function)
        #expect(
            sema.symbols.symbol(getFunctionSymbol)?.flags.contains(.operatorFunction) == true,
            "get must be marked as operator function"
        )
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
        #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])
        #expect(signature.classTypeParameterCount == 0)
    }

    @Test func testCPointerGetFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.get

        fun <T : CPointed> load(ptr: CPointer<T>, index: Int): T {
            return ptr[index]
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.get to resolve via indexing syntax, got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let getFQName = ["kotlinx", "cinterop", "get"].map { interner.intern($0) }
        let getCandidates = Set(sema.symbols.lookupAll(fqName: getFQName))
        let indexedAccess = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case .indexedAccess = expr
            else {
                return nil
            }
            return exprID
        }.first)
        let chosen = try #require(
            sema.bindings.callBinding(for: indexedAccess)?.chosenCallee,
            "Expected CPointer.get indexed access to bind a callee"
        )
        #expect(getCandidates.contains(chosen))
    }
}
#endif
