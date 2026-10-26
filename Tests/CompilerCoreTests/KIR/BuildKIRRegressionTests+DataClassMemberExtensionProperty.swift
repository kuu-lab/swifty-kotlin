#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    // KUU-3520: a member extension property may share a name with a data
    // class's primary-constructor property without replacing its component.
    @Test
    func dataClassComponentUsesConstructorPropertyWithSameNamedMemberExtension() throws {
        try withTemporaryFile(contents: """
        data class A(val x: Int) {
            val Int.x: Int get() = this
        }
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)

            try runToLowering(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")

            let sema = try #require(context.sema)
            let module = try #require(context.kir)
            let interner = context.interner
            let component = try #require(sema.symbols.lookupAll(fqName: [
                interner.intern("A"), interner.intern("component1"),
            ]).first { sema.symbols.symbol($0)?.kind == .function })
            let function = try #require(module.arena.function(for: component))

            #expect(function.body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == interner.intern("kk_array_get_inbounds")
            }, "component1() should read the primary-constructor property's backing field")
        }
    }
}
#endif
