#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        let outerFieldSymbol = try #require(sema.symbols.outerInstanceFieldSymbol(for: innerSymbol))
        let yFieldSymbol = try #require(sema.symbols.lookup(fqName: innerFQ + [interner.intern("y")]))
        #expect(ownFields.map(\.id) == [outerFieldSymbol, yFieldSymbol],
                       "expected $outer to be reserved before Inner's own y, got: \(ownFields.map { interner.resolve($0.name) })")

        #expect(layout.fieldOffsets[outerFieldSymbol] == 2)
        #expect(layout.fieldOffsets[yFieldSymbol] == 3)
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
            kirCalls(to: .objectNew, in: mainBody, interner: ctx.interner).count == 2,
            "expected Outer(1) and Inner(2) to each allocate their own object, got callees: \(mainCallees)"
        )

        let ctorBody = try findKIRFunctionBody(named: "Inner", in: module, interner: ctx.interner)
        let ctorCallees = extractCallees(from: ctorBody, interner: ctx.interner)
        #expect(
            !kirCalls(to: .arraySet, in: ctorBody, interner: ctx.interner).isEmpty,
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
        let readCount = kirCalls(to: .arrayGetInbounds, in: body, interner: ctx.interner).count
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
        let wrappedValues = kirCalls(to: .functionCreate(arity: 1), in: body, interner: ctx.interner).compactMap(\.result)
        try #require(!wrappedValues.isEmpty, "Expected a function value retaining the captured suffix")
        // Receiver-adapted materialization can wrap the same lambda more than
        // once (e.g. __kk_function_copy_description chains); the constructor
        // must receive one of those wrapped values, not the bare symbol.
        let constructor = try findKIRFunction(named: "Inner", in: module, interner: ctx.interner)
        #expect(kirCalls(to: constructor.symbol, in: body).contains {
            $0.arguments.dropFirst().contains { wrappedValues.contains($0) }
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

    @Test func testBoundOuterCallableReferenceCapturesReceiverAcrossNestedInnerClasses() throws {
        let ctx = makeContextFromSource("""
        class Outer {
            fun greet(extra: Int): String = "outer:$extra"
            inner class Inner {
                inner class Deep {
                    fun make(): String {
                        val obj = object {
                            fun show(): String {
                                val ref = this@Outer::greet
                                return ref(3)
                            }
                        }
                        return obj.show()
                    }
                }
            }
        }
        fun main() {
            val outer = Outer()
            println(outer.Inner().Deep().make())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let references = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .callableRef(_, member, _) = expr,
                  ctx.interner.resolve(member) == "greet"
            else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        let reference = try #require(references.first)
        #expect(!sema.bindings.isUnboundCallableRef(reference))

        let module = try #require(ctx.kir)
        let show = try findKIRFunctionBody(named: "show", in: module, interner: ctx.interner)
        let adapterCalls = kirCalls(in: show).filter {
            ctx.interner.resolve($0.callee).hasPrefix("kk_function_value_adapter_")
        }
        #expect(adapterCalls.count == 1)
        #expect(adapterCalls.allSatisfy { $0.arguments.count == 2 }, "The bound reference must pass its captured receiver and explicit argument.")
    }

    @Test func testQualifiedOuterPropertyAssignmentAfterCallIsEmitted() throws {
        let ctx = makeContextFromSource("""
        class Outer {
            var counter: Int = 0
            fun greet(extra: Int): String = "outer:$extra"
            inner class Inner {
                inner class Deep {
                    fun make(): Int {
                        val obj = object {
                            fun show(): Int {
                                val greeting = this@Outer.greet(5)
                                this@Outer.counter = 10
                                this@Outer.counter += 1
                                return this@Outer.counter
                            }
                        }
                        return obj.show()
                    }
                }
            }
        }
        fun main() {
            val outer = Outer()
            println(outer.Inner().Deep().make())
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")

        let ast = try #require(ctx.ast)
        let assignments = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .memberAssign(_, name, _, _) = expr,
                  ctx.interner.resolve(name) == "counter"
            else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(assignments.count == 1)

        let module = try #require(ctx.kir)
        let show = try findKIRFunctionBody(named: "show", in: module, interner: ctx.interner)
        let stores = kirCalls(to: .arraySet, in: show, interner: ctx.interner)
        #expect(stores.count == 2, "Expected plain assignment and compound assignment to store the outer property.")
    }

    /// KUU-4454: an inner class reading an *enclosing* class's property with
    /// a custom getter must dispatch the accessor on the `$outer` instance,
    /// not on the inner `this` — otherwise the getter applies the owner's
    /// field offsets to the wrong object (garbage reads, or a
    /// `kk_array_get_inbounds` panic when the offset exceeds the inner
    /// instance's slot count, as in `ReentrantLock.ConditionObject`).
    @Test func testInnerClassOuterCustomGetterReceivesOuterInstance() throws {
        let ctx = makeContextFromSource("""
        class Outer {
            private var x = 10
            val doubled: Int get() = x * 2
            inner class Inner {
                fun read(): Int = doubled
            }
        }
        fun main() {
            val i = Outer().Inner()
            val v = i.read()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError,
                       "Expected inner-class program to lower to KIR without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
        let hopResults = Set(kirCalls(to: .arrayGetInbounds, in: body, interner: ctx.interner).compactMap(\.result))
        let getCall = try #require(
            kirCalls(in: body).first { ctx.interner.resolve($0.callee) == "get" },
            "expected a `get` accessor call in Inner.read(), got: \(extractCallees(from: body, interner: ctx.interner))"
        )
        #expect(
            hopResults.contains(getCall.arguments[0]),
            "the getter must receive the $outer-hopped receiver, not the inner `this`"
        )
    }

    /// KUU-4454: the write side of the same bug — a bare assignment to an
    /// enclosing class's setter-backed property inside an inner class must
    /// invoke the setter on the `$outer` instance.
    @Test func testInnerClassOuterCustomSetterReceivesOuterInstance() throws {
        let ctx = makeContextFromSource("""
        class Outer {
            private var x = 10
            var doubled: Int
                get() = x * 2
                set(v) { x = v / 2 }
            inner class Inner {
                fun bump() { doubled = 30 }
            }
        }
        fun main() {
            val i = Outer().Inner()
            i.bump()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError,
                       "Expected inner-class program to lower to KIR without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "bump", in: module, interner: ctx.interner)
        let hopResults = Set(kirCalls(to: .arrayGetInbounds, in: body, interner: ctx.interner).compactMap(\.result))
        let setCall = try #require(
            kirCalls(in: body).first { ctx.interner.resolve($0.callee) == "set" },
            "expected a `set` accessor call in Inner.bump(), got: \(extractCallees(from: body, interner: ctx.interner))"
        )
        #expect(
            hopResults.contains(setCall.arguments[0]),
            "the setter must receive the $outer-hopped receiver, not the inner `this`"
        )
    }
}
#endif
