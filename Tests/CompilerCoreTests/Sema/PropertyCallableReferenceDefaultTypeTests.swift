#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-496 follow-up: `inferCallableRefExpr` (`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`)
/// used to fall back to the property's own *value* type when a property
/// callable reference (`Type::property`, `instance::property`, or bare
/// `::property`) had no expected type to adopt — e.g. `val ref = C::v` was
/// typed as `Int` instead of `KProperty1<C, Int>`. Since the KIR wrapper that
/// makes `is KProperty<*>` etc. work is only emitted when the bound type is
/// literally `KProperty0`/`KMutableProperty0`/`KProperty1`/`KMutableProperty1`
/// (see `LambdaLowerer+PropertyReferenceLowering.swift`), this silently
/// produced wrong values at runtime (observed: `println(C::v)` printed `0`).
///
/// These tests fix the Sema-level regression: a property callable reference
/// must infer to a real `KPropertyN`/`KMutablePropertyN` type even without an
/// expected type context, matching what `Type::method` already does for
/// function references.
@Suite
struct PropertyCallableReferenceDefaultTypeTests {
    private func classTypeSymbol(
        for exprID: ExprID,
        sema: SemaModule
    ) throws -> (symbol: SemanticSymbol, args: [TypeArg]) {
        let exprType = try #require(sema.bindings.exprTypes[exprID])
        guard case let .classType(classType) = sema.types.kind(of: exprType) else {
            Issue.record("Expected a class type for the callable reference, got \(sema.types.kind(of: exprType))")
            throw TestFailure.unexpectedShape
        }
        let symbol = try #require(sema.symbols.symbol(classType.classSymbol))
        return (symbol, classType.args)
    }

    private enum TestFailure: Error { case unexpectedShape }

    @Test func testUnboundImmutablePropertyReferenceInfersKProperty1WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        class C(val v: Int)
        fun main() {
            val ref = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, args) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty1"],
            "C::v without an expected type should infer KProperty1<C, Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
        #expect(args.count == 2, "KProperty1 takes two type arguments (owner, value).")
    }

    @Test func testBoundImmutablePropertyReferenceInfersKProperty0WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        class C(val v: Int)
        fun main(c: C) {
            val ref = c::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, args) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty0"],
            "c::v without an expected type should infer KProperty0<Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
        #expect(args.count == 1, "KProperty0 takes one type argument (value).")
    }

    @Test func testUnboundMutablePropertyReferenceInfersKMutableProperty1WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        class C(var v: Int)
        fun main() {
            val ref = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, _) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KMutableProperty1"],
            "C::v of a `var` property without an expected type should infer KMutableProperty1<C, Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
    }

    @Test func testBareTopLevelPropertyReferenceInfersKProperty0WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, args) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty0"],
            "::answer without an expected type should infer KProperty0<Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
        #expect(args.count == 1, "KProperty0 takes one type argument (value).")
    }

    /// An explicit expected type must still win over the default (unchanged
    /// pre-existing behavior — this test just pins it so a future change to
    /// the default-inference path doesn't accidentally start overriding it).
    @Test func testExplicitExpectedTypeStillWinsOverDefaultInference() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KProperty1
        class C(val v: Int)
        fun main() {
            val ref: KProperty1<C, Int> = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, _) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty1"])
    }
}
#endif
