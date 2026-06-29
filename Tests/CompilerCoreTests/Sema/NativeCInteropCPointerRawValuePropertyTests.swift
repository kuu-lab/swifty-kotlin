#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerRawValuePropertyTests {
    @Test func testCPointerRawValuePropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.rawValue surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)])
            return try #require(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))
        let cPointerFQName = try #require(sema.symbols.symbol(cPointerSymbol)?.fqName)
        let rawValueSymbol = try #require(
            sema.symbols.lookup(fqName: cPointerFQName + [interner.intern("rawValue")]),
            "CPointer.rawValue must be registered"
        )

        #expect(sema.symbols.symbol(rawValueSymbol)?.kind == .property)
        #expect(sema.symbols.parentSymbol(for: rawValueSymbol) == cPointerSymbol)
        #expect(sema.symbols.propertyType(for: rawValueSymbol) == nativePtrType)
    }

    @Test func testCPointerRawValuePropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.NativePtr

        fun <T : CPointed> raw(value: CPointer<T>): NativePtr {
            return value.rawValue
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.rawValue to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
