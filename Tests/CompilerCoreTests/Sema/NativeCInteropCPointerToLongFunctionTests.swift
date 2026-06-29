#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerToLongFunctionTests {
    @Test func testCPointerToLongFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer<T>?.toLong() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let cPointedType = try cinteropType("CPointed")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let toLongFQName = cinteropPkg + [interner.intern("toLong")]
        let toLongCandidates = sema.symbols.lookupAll(fqName: toLongFQName)

        let toLong = try #require(toLongCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                  receiverClassType.classSymbol == cPointerSymbol,
                  receiverClassType.nullability == .nullable
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.longType
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: toLong))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nullable
        )))
        let flags = try #require(sema.symbols.symbol(toLong)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(sema.symbols.parentSymbol(for: toLong) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.receiverType == expectedReceiverType)
        #expect(signature.returnType == sema.types.longType)
        #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
        #expect(sema.symbols.parentSymbol(for: typeParameter) == toLong)
    }

    @Test func testCPointerToLongFunctionLinksToRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let toLongFQName = cinteropPkg + [interner.intern("toLong")]
        let toLongCandidates = sema.symbols.lookupAll(fqName: toLongFQName)
        let cPointerSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")])
        )
        let toLong = try #require(toLongCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            guard let receiverType = signature.receiverType,
                  case let .classType(cls) = sema.types.kind(of: receiverType),
                  cls.classSymbol == cPointerSymbol,
                  cls.nullability == .nullable
            else { return false }
            return signature.parameterTypes.isEmpty && signature.returnType == sema.types.longType
        })
        #expect(sema.symbols.externalLinkName(for: toLong) == "kk_cpointer_toLong", "CPointer<T>?.toLong() must link to kk_cpointer_toLong")
    }

    @Test func testCPointerToLongFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun pointerAsLong(p: CPointer<ByteVar>?): Long {
            return p.toLong()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer<ByteVar>?.toLong() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
