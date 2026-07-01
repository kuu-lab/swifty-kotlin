#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerUShortVarToKStringFunctionTests {
    @Test func testCPointerUShortVarToKStringFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let uShortVarSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]))
        let uShortVarType = sema.types.make(.classType(ClassType(classSymbol: uShortVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(uShortVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        #expect(try #require(sema.symbols.symbol(fn)?.flags).contains(.synthetic))
    }

    @Test func testCPointerUShortVarToKStringFunctionLinksToRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let uShortVarSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]))
        let uShortVarType = sema.types.make(.classType(ClassType(classSymbol: uShortVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(uShortVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        #expect(sema.symbols.externalLinkName(for: fn) == "kk_cpointer_toKStringFromUtf16", "CPointer<UShortVar>.toKString() must link to kk_cpointer_toKStringFromUtf16")
    }

    @Test func testCPointerUShortVarToKStringFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.UShortVar
        import kotlinx.cinterop.toKString

        fun decode(p: CPointer<UShortVar>): String {
            return p.toKString()
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
