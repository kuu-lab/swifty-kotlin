#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerIntVarToKStringFromUtf32FunctionTests {
    @Test func testCPointerIntVarToKStringFromUtf32FunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let intVarSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]))
        let intVarType = sema.types.make(.classType(ClassType(classSymbol: intVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(intVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKStringFromUtf32")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        #expect(try #require(sema.symbols.symbol(fn)?.flags).contains(.synthetic))
    }

    @Test func testCPointerIntVarToKStringFromUtf32FunctionLinksToRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let intVarSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]))
        let intVarType = sema.types.make(.classType(ClassType(classSymbol: intVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(intVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKStringFromUtf32")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        #expect(sema.symbols.externalLinkName(for: fn) == "kk_cpointer_toKStringFromUtf32", "CPointer<IntVar>.toKStringFromUtf32() must link to kk_cpointer_toKStringFromUtf32")
    }

    @Test func testCPointerIntVarToKStringFromUtf32FunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.IntVar
        import kotlinx.cinterop.toKStringFromUtf32

        fun decode(p: CPointer<IntVar>): String {
            return p.toKStringFromUtf32()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
