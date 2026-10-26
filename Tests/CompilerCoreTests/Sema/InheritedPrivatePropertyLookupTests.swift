#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct InheritedPrivatePropertyLookupTests {
    @Test func inheritedPrivatePropertiesDoNotShadowPublicInterfaceProperty() throws {
        try withTemporaryFile(contents: """
        interface A { public val c: String get() = "OK" }
        interface B { private val c: String get() = "FAIL" }
        open class C { private val c: String = "FAIL" }
        open class D : C(), A, B { val b = c }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                guard case let .nameRef(name, _) = expr, ctx.interner.resolve(name) == "c" else {
                    return nil
                }
                return ExprID(rawValue: Int32(index))
            }.first)
            let selectedSymbol = try #require(sema.bindings.identifierSymbol(for: reference))
            let publicInterfaceProperty = try #require(sema.symbols.lookup(
                fqName: ["A", "c"].map(ctx.interner.intern)
            ))

            #expect(selectedSymbol == publicInterfaceProperty)
        }
    }
}
#endif
