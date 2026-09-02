#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for KSP-805: implicit kotlin.Any must remain the
/// nominal root without becoming an explicit `super()` delegation target.
@Suite
struct AnyConstructorRegressionTests {

    @Test
    func implicitAnyConstructorDoesNotResolveBareSuperDelegation() throws {
        let source = """
        package ksp805

        class Foo {
            constructor(x: Int) : super()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        #expect(
            codes.contains("KSWIFTK-SEMA-0021") || codes.contains("KSWIFTK-SEMA-0055"),
            "Expected an invalid super() diagnostic, got: \(codes)"
        )
    }

    @Test
    func explicitAnyConstructorRemainsAValidDelegationTarget() throws {
        let source = """
        package ksp805

        class Foo : Any() {
            constructor(x: Int) : super()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        #expect(
            !codes.contains("KSWIFTK-SEMA-0055"),
            "Explicit Any() should resolve super(), got: \(codes)"
        )
    }
}
#endif
