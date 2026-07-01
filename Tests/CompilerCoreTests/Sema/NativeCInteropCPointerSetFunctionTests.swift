#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerSetFunctionTests {
    @Test func testCPointerSetFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.set surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let setFQName = cinteropPkg + [interner.intern("set")]
        let setFunctionSymbol = try #require(
            sema.symbols.lookupAll(fqName: setFQName).first { symbolID in
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
                    && sig.parameterTypes == [sema.types.intType, typeParamType]
                    && sig.returnType == sema.types.unitType
            },
            "kotlinx.cinterop.CPointer<T>.set(index: Int, value: T): Unit must be registered"
        )

        let signature = try #require(sema.symbols.functionSignature(for: setFunctionSymbol))
        let typeParameter = try #require(signature.typeParameterSymbols.first)

        #expect(sema.symbols.symbol(setFunctionSymbol)?.kind == .function)
        #expect(
            sema.symbols.symbol(setFunctionSymbol)?.flags.contains(.operatorFunction) == true,
            "set must be marked as operator function"
        )
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
        #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])
        #expect(signature.classTypeParameterCount == 0)
        #expect(signature.parameterTypes.count == 2)
        #expect(signature.returnType == sema.types.unitType)
    }

    @Test func testCPointerSetFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.set

        fun <T : CPointed> store(ptr: CPointer<T>, index: Int, value: T) {
            ptr[index] = value
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.set to resolve via indexed assignment syntax, got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let setFQName = ["kotlinx", "cinterop", "set"].map { interner.intern($0) }
        let setCandidates = Set(sema.symbols.lookupAll(fqName: setFQName))
        let indexedAssignment = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case .indexedAssign = expr
            else {
                return nil
            }
            return exprID
        }.first)
        let chosen = try #require(
            sema.bindings.callBinding(for: indexedAssignment)?.chosenCallee,
            "Expected CPointer.set indexed assignment to bind a callee"
        )
        #expect(setCandidates.contains(chosen))
    }
}
#endif
