#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for KSP-805: implicit kotlin.Any must remain the
/// nominal root without becoming an explicit `super()` delegation target.
@Suite
struct AnyConstructorRegressionTests {

    @Test
    func genericSecondaryDelegationUsesDeclaredOwnerTypeArguments() throws {
        let source = """
        package ksp557

        open class Base<K, V> {
            constructor(capacity: Int)
        }

        class FromSuper<K, V> : Base<K, V> {
            constructor(capacity: Int) : super(capacity)
        }

        class FromThis<K, V>(capacity: Int) : Base<K, V>(capacity) {
            constructor(capacity: Int, loadFactor: Float) : this(capacity)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Generic delegations should resolve: \(errors)")
    }

    @Test
    func genericSecondaryDelegationStillRejectsWrongArgumentType() throws {
        let source = """
        package ksp557

        open class Base<K, V> {
            constructor(capacity: Int)
        }

        class Wrong<K, V> : Base<K, V> {
            constructor(label: String) : super(label)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

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
