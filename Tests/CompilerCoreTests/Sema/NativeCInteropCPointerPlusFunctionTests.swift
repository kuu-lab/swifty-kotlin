#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerPlusFunctionTests {
    @Test
    func testCPointerPlusFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CPointer.plus surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let plusFQName = cinteropPkg + [interner.intern("plus")]
        let plusCandidates = sema.symbols.lookupAll(fqName: plusFQName)
        let byteVarOfUpperBound = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("ByteVarOf"),
            args: [.star],
            nullability: .nonNull
        )))
        let cPointerVarOfUpperBound = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointerVarOf"),
            args: [.star],
            nullability: .nonNull
        )))

        func assertPlusOverload(
            indexType: TypeID,
            upperBound: TypeID,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let plusSymbol = try #require(plusCandidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.parameterTypes == [indexType]
                    && signature.typeParameterUpperBoundsList == [[upperBound]]
            })
            let signature = try #require(sema.symbols.functionSignature(for: plusSymbol))
            let typeParameter = try #require(signature.typeParameterSymbols.first)
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParameter,
                nullability: .nonNull
            )))
            let expectedPointerType = sema.types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(typeParameterType)],
                nullability: .nonNull
            )))
            let parameterSymbol = try #require(signature.valueParameterSymbols.first)
            let flags = try #require(sema.symbols.symbol(plusSymbol)?.flags)

            #expect(flags.isSuperset(of: [.synthetic, .inlineFunction, .operatorFunction]))
            #expect(signature.receiverType == expectedPointerType)
            #expect(signature.returnType == expectedPointerType)
            #expect(signature.reifiedTypeParameterIndices.isEmpty)
            #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [upperBound])
            #expect(sema.symbols.symbol(parameterSymbol)?.name == interner.intern("index"))
            #expect(sema.symbols.propertyType(for: parameterSymbol) == indexType)
        }

        try assertPlusOverload(indexType: sema.types.intType, upperBound: byteVarOfUpperBound)
        try assertPlusOverload(indexType: sema.types.longType, upperBound: byteVarOfUpperBound)
        try assertPlusOverload(indexType: sema.types.intType, upperBound: cPointerVarOfUpperBound)
        try assertPlusOverload(indexType: sema.types.longType, upperBound: cPointerVarOfUpperBound)
    }

    @Test
    func testCPointerPlusFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.plus

        fun plusInt(value: CPointer<ByteVar>): CPointer<ByteVar> {
            return value + 1
        }

        fun plusLong(value: CPointer<ByteVar>): CPointer<ByteVar> {
            return value + 1L
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CPointer.plus to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let plusFQName = ["kotlinx", "cinterop", "plus"].map { interner.intern($0) }
        let plusCandidates = Set(sema.symbols.lookupAll(fqName: plusFQName))
        let cpointerPlusBound = ast.arena.exprs.indices.filter { index -> Bool in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case .binary(.add, _, _, _) = expr,
                  let binding = sema.bindings.callBinding(for: exprID)
            else { return false }
            return plusCandidates.contains(binding.chosenCallee)
        }
        #expect(cpointerPlusBound.count == 2, "Expected exactly 2 binary adds bound to CPointer.plus")
    }
}
#endif
