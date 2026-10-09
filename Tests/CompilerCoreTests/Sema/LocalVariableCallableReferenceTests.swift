#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1355: a bare `::name` reference can never denote a local variable or
/// value parameter — kotlinc rejects them with "references to variables
/// aren't supported yet". Local variables are simply invisible to `::`
/// resolution rather than shadowing for it, so a same-named top-level or
/// member property still binds the reference, and local *functions* remain
/// valid targets. Pinning this contract keeps the rejection from being
/// "fixed" into an extension Kotlin does not have, and keeps the legal forms
/// from being rejected together with it.
@Suite
struct LocalVariableCallableReferenceTests {

    // MARK: - Local variables are not valid `::` targets

    @Test func testBareCallableRefRejectsLocalVar() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            var nm = 3
            val p = ::nm
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    @Test func testBareCallableRefRejectsLocalVal() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val nm = 3
            val p = ::nm
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    @Test func testBareCallableRefRejectsParameter() throws {
        let ctx = makeContextFromSource("""
        fun takesParam(x: Int) {
            val p = ::x
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    // MARK: - Locals are invisible to `::`, they do not shadow for it

    @Test func testBareCallableRefBindsTopLevelPropertyShadowedByLocal() throws {
        let ctx = makeContextFromSource("""
        var shadowed = 1
        fun main() {
            var shadowed = 9
            val p = ::shadowed
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let topLevelSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .property, symbol.name == ctx.interner.intern("shadowed") else { return false }
            let parentKind = sema.symbols.parentSymbol(for: symbol.id).flatMap { sema.symbols.symbol($0)?.kind }
            return parentKind == .package || parentKind == nil
        })?.id)
        #expect(
            sema.bindings.identifierSymbols[callableRefExprID] == topLevelSymbol,
            "`::shadowed` must bind the top-level property the local variable shadows"
        )
    }

    @Test func testBareCallableRefBindsMemberPropertyShadowedByLocal() throws {
        let ctx = makeContextFromSource("""
        class C {
            var nm = 0
            fun f() {
                var nm = 1
                val p = ::nm
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let memberSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .property, symbol.name == ctx.interner.intern("nm") else { return false }
            return sema.symbols.parentSymbol(for: symbol.id).flatMap { sema.symbols.symbol($0)?.kind } == .class
        })?.id)
        #expect(
            sema.bindings.identifierSymbols[callableRefExprID] == memberSymbol,
            "`::nm` must bind the member property the local variable shadows"
        )
    }

    // MARK: - Local functions stay referenceable

    @Test func testBareCallableRefToLocalFunctionStillWorks() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            fun localFn() = 1
            val f = ::localFn
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let localFnSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && symbol.name == ctx.interner.intern("localFn")
        })?.id)
        #expect(
            sema.bindings.identifierSymbols[callableRefExprID] == localFnSymbol,
            "`::localFn` must bind the local function symbol"
        )
    }
}
#endif
