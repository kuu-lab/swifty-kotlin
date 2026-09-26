#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-inner-outer: `inner class` members reading/writing an enclosing
/// class's fields must go through the synthetic `$outer` link rather than
/// aliasing whatever the inner class's own field happens to occupy at the
/// same layout slot. See `Scripts/diff_cases/inner_class_outer_instance.kt`
/// for the end-to-end repro.
@Suite
struct InnerClassOuterInstanceTests {
    private static let source = """
    class Outer(val x: Int) {
        inner class Inner(val y: Int) {
            fun sum() = x + y
        }
    }
    fun main() {
        val inner = Outer(1).Inner(2)
    }
    """

    @Test func testInnerClassReservesOuterFieldAsFirstOwnSlot() throws {
        let ctx = makeContextFromSource(Self.source)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError),
                       "Expected inner-class program to compile without sema errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let outerFQ = [interner.intern("Outer")]
        let innerFQ = outerFQ + [interner.intern("Inner")]
        let innerSymbol = try #require(sema.symbols.lookup(fqName: innerFQ))
        #expect(sema.symbols.symbol(innerSymbol)?.flags.contains(.innerClass) == true)

        let layout = try #require(sema.symbols.nominalLayout(for: innerSymbol))
        #expect(layout.instanceFieldCount == 2, "expected $outer + y, got instanceFieldCount=\(layout.instanceFieldCount)")

        let ownFields = sema.symbols.children(ofFQName: innerFQ)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .field || $0.kind == .property }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        #expect(ownFields.map { interner.resolve($0.name) } == ["$outer", "y"],
                       "expected $outer to be reserved before Inner's own y, got: \(ownFields.map { interner.resolve($0.name) })")

        let outerFieldSymbol = try #require(sema.symbols.outerInstanceFieldSymbol(for: innerSymbol))
        #expect(outerFieldSymbol == ownFields[0].id)
        #expect(layout.fieldOffsets[outerFieldSymbol] == 2)
        #expect(layout.fieldOffsets[ownFields[1].id] == 3)
    }

    @Test func testConstructorStoresOuterInstanceLink() throws {
        let ctx = makeContextFromSource(Self.source)
        try runToKIR(ctx)
        #expect(!(ctx.diagnostics.hasError),
                       "Expected inner-class program to lower to KIR without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        // `outer.Inner(2)` must allocate a genuine second object (its own
        // `kk_object_new`) and store `outer` into its `$outer` slot before
        // `<init>` runs -- not reuse `outer`'s own instance as `Inner`'s
        // `this` (the root cause this fix addresses).
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(
            mainCallees.filter { $0 == "kk_object_new" }.count == 2,
            "expected Outer(1) and Inner(2) to each allocate their own object, got callees: \(mainCallees)"
        )

        let ctorBody = try findKIRFunctionBody(named: "Inner", in: module, interner: ctx.interner)
        let ctorCallees = extractCallees(from: ctorBody, interner: ctx.interner)
        #expect(
            ctorCallees.contains("kk_array_set"),
            "expected Inner's constructor to store $outer (and y) into the new instance, got: \(ctorCallees)"
        )
    }

    @Test func testMemberFunctionReadsOuterFieldThroughOuterLink() throws {
        let ctx = makeContextFromSource(Self.source)
        try runToKIR(ctx)
        #expect(!(ctx.diagnostics.hasError),
                       "Expected inner-class program to lower to KIR without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        // `x + y` inside `Inner.sum()` must read `y` directly off Inner's
        // own `this` (1 read), but `x` only after first loading `$outer`
        // (1 hop) and then reading `x` off that (1 read) -- 3 total.
        // Aliasing (the bug) would collapse this to 2 reads, both against
        // Inner's own `this`, silently reusing whatever field occupies the
        // slot Outer's layout assigned `x`.
        let body = try findKIRFunctionBody(named: "sum", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        let readCount = callees.filter { $0 == "kk_array_get_inbounds" }.count
        #expect(readCount == 3, "expected 3 kk_array_get_inbounds calls ($outer hop + x + y), got \(readCount): \(callees)")
    }
}
#endif
