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

    @Test(arguments: [false, true])
    func testExplicitConstructorDispatchesDefaultArguments(safe: Bool) throws {
        let receiver = safe ? "outer?.Inner()" : "outer.Inner()"
        let ctx = makeContextFromSource("""
        class Outer(val seed: Int) {
            inner class Inner(val n: Int = seed + 7)
        }
        fun make(outer: Outer\(safe ? "?" : "")) {
            val inner = \(receiver)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("Inner$default"), "Expected default stub dispatch, got: \(callees)")
        #expect(!callees.contains("Inner"), "Defaulted construction must not call the real constructor directly")
    }

    @Test(arguments: [false, true])
    func testExplicitConstructorMaterializesCapturedReceiverLambda(safe: Bool) throws {
        let receiver = safe ? "outer?.Inner" : "outer.Inner"
        let ctx = makeContextFromSource("""
        class Outer {
            inner class Inner(val block: String.() -> String)
        }
        fun make(outer: Outer\(safe ? "?" : ""), suffix: String) {
            val inner = \(receiver) { this + suffix }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
        let wrappedValues = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_function_create_1"
            else { return nil }
            return result
        }
        let wrappedValue = try #require(wrappedValues.first, "Expected a function value retaining the captured suffix")
        #expect(body.contains { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "Inner"
            else { return false }
            return arguments.dropFirst().contains(wrappedValue)
        }, "The constructor must receive the wrapped function value")
    }

    /// BUG-inner-outer: `this@Outer` referenced from inside an object
    /// literal's own member function, where `Outer` is reachable only
    /// through *two* `inner class` `$outer` hops (the object literal sits
    /// inside `Middle`, itself `inner` to `Outer`). This previously
    /// regressed by misclassifying the qualified-`this` receiver as a
    /// class-name (static/companion) receiver, which made `.tag` lower to
    /// an unresolved bare call instead of a property read. See
    /// `Scripts/diff_cases/inner_class_qualified_this_outer_chain.kt`
    /// (verified against kotlinc: `hello/world`).
    @Test func testQualifiedThisResolvesAncestorTwoOuterHopsFromObjectLiteral() throws {
        let ctx = makeContextFromSource("""
        class Outer(val tag: String) {
            inner class Middle(val mtag: String) {
                fun make(): String {
                    val obj = object {
                        fun show(): String {
                            return this@Outer.tag + "/" + this@Middle.mtag
                        }
                    }
                    return obj.show()
                }
            }
        }
        fun main() {
            val o = Outer("hello")
            val m = o.Middle("world")
            val result = m.make()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "show", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(!callees.contains("tag"), "this@Outer.tag must not lower to an unresolved bare call, got: \(callees)")
        #expect(!callees.contains("mtag"), "this@Middle.mtag must not lower to an unresolved bare call, got: \(callees)")
    }

    /// BUG-inner-outer: an object literal's member function reads an
    /// immutable property declared on a class reachable only through *two*
    /// `inner class` `$outer` hops. Capture analysis previously only
    /// considered the immediate enclosing class, so `value` was never
    /// captured and the read crashed or returned garbage. See
    /// `Scripts/diff_cases/inner_class_object_literal_outer_property_capture.kt`
    /// (verified against kotlinc: `42`).
    @Test func testObjectLiteralCapturesPropertyTwoOuterHopsOut() throws {
        let ctx = makeContextFromSource("""
        class Outer(val value: Int) {
            inner class Inner {
                inner class Deep {
                    fun make(): Int {
                        val obj = object {
                            fun compute(): Int {
                                return value + 1
                            }
                        }
                        return obj.compute()
                    }
                }
            }
        }
        fun main() {
            val o = Outer(41)
            val i = o.Inner()
            val d = i.Deep()
            val result = d.make()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(!callees.contains("value"), "value must not lower to an unresolved bare call, got: \(callees)")
    }
}
#endif
