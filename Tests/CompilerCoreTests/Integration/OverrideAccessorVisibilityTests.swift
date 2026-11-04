#if canImport(Testing)
import Foundation
import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

/// KUU-4142: an `override` property's accessors must not weaken the
/// overridden accessor's visibility, and may only widen it. kotlinc 2.4.20
/// rejects a narrower accessor with `cannot weaken access privilege`
/// (`CANNOT_WEAKEN_ACCESS_PRIVILEGE`) and an unordered `protected`/`internal`
/// pairing with `cannot change access privilege`
/// (`CANNOT_CHANGE_ACCESS_PRIVILEGE`), always naming `accessor` and the
/// declaring supertype. An accessor that spells no modifier inherits the
/// overridden accessor's visibility — unless the override property spells
/// its own, which the implicit accessors then take instead.
@Suite struct OverrideAccessorVisibilityTests {
    private static let weakenCode = "KSWIFTK-SEMA-0478"
    private static let changeCode = "KSWIFTK-SEMA-0479"

    private static let weakenCases: [String] = [
        // The ticket's minimal reproducer: public base setter narrowed.
        """
        open class B { open var w: Int = 0 }
        class C : B() {
            override var w: Int = 1
                private set
        }
        """,
        // `protected` base setter narrowed to `private`.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            override var w: Int = 1
                private set
        }
        """,
        // `internal` base setter narrowed to `private`.
        """
        open class B { open var w: Int = 0
            internal set }
        class C : B() {
            override var w: Int = 1
                private set
        }
        """,
        // `internal` is narrower than `public`, even in the same module.
        """
        open class B { open var w: Int = 0 }
        class C : B() {
            override var w: Int = 1
                internal set
        }
        """,
        // The getter follows the same rule.
        """
        open class B { open val v: Int = 0 }
        class C : B() {
            override val v: Int = 1
                private get
        }
        """,
        // Interface properties are implicitly public.
        """
        interface I { var w: Int }
        class C : I {
            override var w: Int = 1
                private set
        }
        """,
        // The implicit base accessor's visibility is resolved through the
        // override chain: C's setter is checked against M's inherited
        // `protected set`.
        """
        open class B { open var w: Int = 0
            protected set }
        open class M : B() { override var w: Int = 1 }
        class C : M() {
            override var w: Int = 2
                private set
        }
        """,
    ]

    private static let changeCases: [String] = [
        // `protected` base property (implicit `protected set`) vs `internal`.
        """
        open class B { protected open var w: Int = 0 }
        class C : B() {
            override var w: Int = 1
                internal set
        }
        """,
        // `protected` base setter vs `internal` — unordered, so a change.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            override var w: Int = 1
                internal set
        }
        """,
        // `internal` base setter vs `protected` — the other direction.
        """
        open class B { open var w: Int = 0
            internal set }
        class C : B() {
            override var w: Int = 1
                protected set
        }
        """,
        // An explicit property modifier flows to implicit accessors:
        // `internal` property vs `protected` base members.
        """
        open class B { protected open var w: Int = 0 }
        class C : B() {
            internal override var w: Int = 1
        }
        """,
    ]

    private static let acceptCases: [String] = [
        // Implicit accessors inherit the overridden accessor's visibility.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            override var w: Int = 1
        }
        """,
        // Widening the accessor is legal.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            override var w: Int = 1
                public set
        }
        """,
        """
        open class B { open var w: Int = 0
            internal set }
        class C : B() {
            override var w: Int = 1
                public set
        }
        """,
        // Spelling the same visibility as the overridden accessor is legal.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            override var w: Int = 1
                protected set
        }
        """,
        """
        open class B { internal open var w: Int = 0 }
        class C : B() {
            internal override var w: Int = 1
        }
        """,
        // A wider property visibility keeps the inherited accessor
        // visibility.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            public override var w: Int = 1
        }
        """,
        // A `var` may override a `val`; the added setter has no overridden
        // accessor to weaken.
        """
        open class B { protected open val v: Int = 0 }
        class C : B() {
            override var v: Int = 1
                private set
        }
        """,
        // An explicit `get` node without modifiers still inherits.
        """
        open class B { open var w: Int = 0 }
        class C : B() {
            override var w: Int = 1
                get() = field
        }
        """,
    ]

    private func diagnose(_ source: String) throws -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            diagnostics = ctx.diagnostics.diagnostics
        }
        return diagnostics
    }

    @Test(arguments: weakenCases)
    func testWeakenedOverrideAccessorVisibilityIsRejected(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.weakenCode
                && $0.message.hasPrefix("cannot weaken access privilege")
        }, "expected \(Self.weakenCode) in \(diagnostics)")
    }

    @Test(arguments: changeCases)
    func testChangedOverrideAccessorVisibilityIsRejected(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.changeCode
                && $0.message.hasPrefix("cannot change access privilege")
        }, "expected \(Self.changeCode) in \(diagnostics)")
    }

    /// kotlinc reports the diagnostic on the element spelling the effective
    /// visibility: an accessor node when one exists, otherwise the property's
    /// own modifier. Both positions are covered here.
    @Test func testOverrideAccessorDiagnosticsMatchKotlincPositionsAndMessages() throws {
        let diagnostics = try diagnose("""
        open class B { open var w: Int = 0 }
        class C : B() {
            override var w: Int = 1
                private set
        }
        """)
        #expect(diagnostics.contains {
            $0.code == Self.weakenCode
                && $0.message == "cannot weaken access privilege private for 'accessor' in 'B'."
        }, "expected weaken diagnostic in \(diagnostics)")

        // `protected override var`: the property modifier flows to both
        // implicit accessors; kotlinc deduplicates the identical reports.
        let deduped = try diagnose("""
        open class B { open var w: Int = 0 }
        class C : B() {
            protected override var w: Int = 1
        }
        """)
        let weakenCount = deduped.filter {
            $0.code == Self.weakenCode
                && $0.message == "cannot weaken access privilege protected for 'accessor' in 'B'."
        }.count
        #expect(weakenCount == 1, "expected one deduplicated diagnostic in \(deduped)")

        // An explicit `get` node reports at the accessor while the implicit
        // setter reports at the property modifier: two distinct positions.
        let twoRanges = try diagnose("""
        open class B { open var w: Int = 0 }
        class C : B() {
            protected override var w: Int = 1
                get() = field
        }
        """)
        let rangedCount = twoRanges.filter { $0.code == Self.weakenCode }.count
        #expect(rangedCount == 2, "expected two accessor-position diagnostics in \(twoRanges)")

        // `internal override var` on a public-property/`protected`-setter
        // base weakens the getter (internal < public) and changes the setter
        // (internal vs protected, unordered) — different codes, both kept.
        let both = try diagnose("""
        open class B { open var w: Int = 0
            protected set }
        class C : B() {
            internal override var w: Int = 1
        }
        """)
        #expect(both.contains {
            $0.code == Self.weakenCode
                && $0.message == "cannot weaken access privilege internal for 'accessor' in 'B'."
        }, "expected weaken diagnostic in \(both)")
        #expect(both.contains {
            $0.code == Self.changeCode
                && $0.message == "cannot change access privilege internal for 'accessor' in 'B'."
        }, "expected change diagnostic in \(both)")
    }

    @Test(arguments: acceptCases)
    func testLegalOverrideAccessorVisibilityIsAccepted(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(!diagnostics.contains {
            $0.code == Self.weakenCode || $0.code == Self.changeCode
        }, "unexpected override accessor visibility diagnostic in \(diagnostics)")
        #expect(!diagnostics.contains { $0.severity == .error },
                "expected no errors in \(diagnostics)")
    }

    /// KUU-4152: the implicit setter of an `override var` inherits the
    /// overridden setter's visibility at *use sites* too, not just in the
    /// declaration-side check. kotlinc reports `cannot access 'w': it is
    /// protected in 'C'` for a write through the derived type.
    @Test(arguments: [
        // The ticket's minimal reproducer.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() { override var w: Int = 1 }
        fun write(c: C) { c.w = 5 }
        """,
        // The inherited visibility propagates down longer override chains.
        """
        open class A { open var w: Int = 0
            protected set }
        open class B : A() { override var w: Int = 1 }
        class C : B() { override var w: Int = 2 }
        fun write(c: C) { c.w = 5 }
        """,
        // A `private set` base propagates its own visibility.
        """
        open class B { open var w: Int = 0
            private set }
        open class M : B() { override var w: Int = 1 }
        class C : M() { override var w: Int = 2 }
        fun write(c: C) { c.w = 5 }
        """,
    ])
    func testImplicitOverrideSetterInheritsBaseVisibilityAtUseSite(source: String) throws {
        let diagnostics = try diagnose(source)
        // 0041 is `protected`/`internal`; a `private` setter reports 0040.
        #expect(diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0041" || $0.code == "KSWIFTK-SEMA-0040"
        }, "expected a use-site access diagnostic in \(diagnostics)")
    }

    /// The same propagation must hold for body-nested declarations, whose
    /// member symbols are bound during body inference — before the deferred
    /// override validation could store the inherited visibility.
    @Test(arguments: [
        // Local class: the write is checked inside the same body.
        """
        open class B { open var w: Int = 0
            protected set }
        fun outer() {
            class C : B() { override var w: Int = 1 }
            val c = C()
            c.w = 5
        }
        """,
        // Anonymous object: the write happens through the object's member.
        """
        open class B { open var w: Int = 0
            protected set }
        val o = object : B() { override var w: Int = 1 }
        fun write() { o.w = 5 }
        """,
    ])
    func testBodyNestedImplicitOverrideSetterInheritsBaseVisibility(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0041" || $0.code == "KSWIFTK-SEMA-0040"
        }, "expected a use-site access diagnostic in \(diagnostics)")
    }

    /// Companion accept cases: reading stays public, a `protected` setter
    /// remains writable inside a subclass, and an explicit `public` property
    /// modifier widens the implicit setter so external writes stay legal —
    /// all matching kotlinc.
    @Test(arguments: [
        // Reading uses the member visibility, which stays public.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() { override var w: Int = 1 }
        fun read(c: C): Int = c.w
        """,
        // `protected` is still accessible inside a subclass.
        """
        open class B { open var w: Int = 0
            protected set }
        open class C : B() { override var w: Int = 1 }
        class D : C() { fun use() { w = 5 } }
        """,
        // An explicit property modifier overrides the inherited accessor
        // visibility; widening `protected set` to `public` is legal.
        """
        open class B { open var w: Int = 0
            protected set }
        class C : B() { public override var w: Int = 1 }
        fun write(c: C) { c.w = 5 }
        """,
    ])
    func testImplicitOverrideSetterUseSiteAcceptCases(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(!diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0041"
        }, "unexpected use-site access diagnostic in \(diagnostics)")
        #expect(!diagnostics.contains { $0.severity == .error },
                "expected no errors in \(diagnostics)")
    }
}
#endif
