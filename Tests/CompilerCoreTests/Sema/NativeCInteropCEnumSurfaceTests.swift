#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCEnumSurfaceTests {
    @Test func testCEnumInterfaceSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CEnum surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cEnumSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CEnum")])
        )
        let valueSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CEnum"), interner.intern("value")])
        )
        let deprecated = sema.symbols.annotations(for: cEnumSymbol).first {
            $0.annotationFQName == "kotlin.Deprecated"
        }

        #expect(sema.symbols.symbol(cEnumSymbol)?.kind == .interface)
        #expect(sema.symbols.propertyType(for: cEnumSymbol) == sema.types.make(.classType(ClassType(
            classSymbol: cEnumSymbol,
            args: [],
            nullability: .nonNull
        ))))
        #expect(deprecated != nil)
        #expect(deprecated?.arguments == ["message = \"Will be removed.\""])
        #expect(sema.symbols.symbol(valueSymbol)?.kind == .property)
        #expect(sema.symbols.propertyType(for: valueSymbol) == sema.types.anyType)
        #expect(sema.symbols.symbol(valueSymbol)?.flags.contains(.abstractType) == true)
    }

    @Test func testCEnumValuePropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CEnum

        @Suppress("DEPRECATION")
        fun readValue(value: CEnum): Any {
            return value.value
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CEnum.value to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
