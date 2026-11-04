#if canImport(Testing)
import Foundation
import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

/// KUU-4153: member-level `override` visibility uses kotlinc's
/// `Visibilities.compare` partial order — `private` is narrower than every
/// visibility and `public` wider than every visibility, while `protected`
/// and `internal` are unordered relative to each other. There is no
/// exemption for `internal` narrowing inside the same module: a strictly
/// narrower override reports `cannot weaken access privilege`
/// (`CANNOT_WEAKEN_ACCESS_PRIVILEGE`, KSWIFTK-SEMA-0478) and an unordered
/// pairing reports `cannot change access privilege`
/// (`CANNOT_CHANGE_ACCESS_PRIVILEGE`, KSWIFTK-SEMA-0479), naming the member
/// itself rather than `accessor`.
///
/// KUU-4155: `private` and `override` are an incompatible modifier pair —
/// kotlinc reports `modifier 'private' is incompatible with 'override'` and
/// the reverse (`KSWIFTK-SEMA-0402`) on functions, properties, and even
/// declarations where `override` is not applicable at all.
@Suite struct OverrideMemberVisibilityTests {
    private static let weakenCode = "KSWIFTK-SEMA-0478"
    private static let changeCode = "KSWIFTK-SEMA-0479"
    private static let pairCode = "KSWIFTK-SEMA-0402"

    private static let weakenCases: [String] = [
        // The ticket reproducer: `internal` narrows `public`, same module.
        """
        open class B { open fun f() = 0 }
        class C : B() { internal override fun f() = 1 }
        """,
        // `private` narrows every visibility.
        """
        open class B { open fun f() = 0 }
        class C : B() { private override fun f() = 1 }
        """,
        """
        open class B { protected open fun f() = 0 }
        class C : B() { private override fun f() = 1 }
        """,
        """
        open class B { internal open fun f() = 0 }
        class C : B() { private override fun f() = 1 }
        """,
        // `protected` narrows `public`.
        """
        open class B { open fun f() = 0 }
        class C : B() { protected override fun f() = 1 }
        """,
        // Interface members are implicitly public; `internal` narrows it.
        """
        interface I { fun f() }
        class C : I { internal override fun f() = 1 }
        """,
    ]

    private static let changeCases: [String] = [
        // `protected` and `internal` are unordered: `protected` child of an
        // `internal` base is a change, not a weakening.
        """
        open class B { internal open fun f() = 0 }
        class C : B() { protected override fun f() = 1 }
        """,
        // The reverse direction is equally unordered.
        """
        open class B { protected open fun f() = 0 }
        class C : B() { internal override fun f() = 1 }
        """,
    ]

    private static let acceptCases: [String] = [
        // Widening is always legal.
        """
        open class B { protected open fun f() = 0 }
        class C : B() { public override fun f() = 1 }
        """,
        """
        open class B { internal open fun f() = 0 }
        class C : B() { public override fun f() = 1 }
        """,
        // Equal visibilities are legal.
        """
        open class B { internal open fun f() = 0 }
        class C : B() { internal override fun f() = 1 }
        """,
        """
        open class B { protected open fun f() = 0 }
        class C : B() { protected override fun f() = 1 }
        """,
        // No visibility modifier keeps the inherited one.
        """
        open class B { open fun f() = 0 }
        class C : B() { override fun f() = 1 }
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
    func testWeakenedOverrideVisibilityIsRejected(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.weakenCode
                && $0.message.hasPrefix("cannot weaken access privilege")
        }, "expected \(Self.weakenCode) in \(diagnostics)")
    }

    @Test(arguments: changeCases)
    func testChangedOverrideVisibilityIsRejected(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.changeCode
                && $0.message.hasPrefix("cannot change access privilege")
        }, "expected \(Self.changeCode) in \(diagnostics)")
    }

    /// The member-level diagnostics name the member and its declaring
    /// supertype, matching kotlinc's message shape.
    @Test func testMemberVisibilityDiagnosticsMatchKotlincMessages() throws {
        let weaken = try diagnose("""
        open class B { open fun f() = 0 }
        class C : B() { internal override fun f() = 1 }
        """)
        #expect(weaken.contains {
            $0.code == Self.weakenCode
                && $0.message == "cannot weaken access privilege internal for 'f' in 'B'."
        }, "expected weaken diagnostic in \(weaken)")

        let change = try diagnose("""
        open class B { internal open fun f() = 0 }
        class C : B() { protected override fun f() = 1 }
        """)
        #expect(change.contains {
            $0.code == Self.changeCode
                && $0.message == "cannot change access privilege protected for 'f' in 'B'."
        }, "expected change diagnostic in \(change)")
    }

    @Test(arguments: acceptCases)
    func testLegalOverrideVisibilityIsAccepted(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(!diagnostics.contains {
            $0.code == Self.weakenCode || $0.code == Self.changeCode
        }, "unexpected override visibility diagnostic in \(diagnostics)")
        #expect(!diagnostics.contains { $0.severity == .error },
                "expected no errors in \(diagnostics)")
    }

    /// KUU-4155: `private` and `override` are incompatible in both
    /// directions — functions, properties, and top-level declarations where
    /// `override` is not even applicable.
    @Test(arguments: [
        """
        open class B { open fun f() = 0 }
        class C : B() { private override fun f() = 1 }
        """,
        """
        open class B { open var w: Int = 0 }
        class C : B() { private override var w: Int = 1 }
        """,
        // Even a top-level function, where `override` is never applicable,
        // reports the pair rather than a "not applicable" diagnostic.
        """
        private override fun f() = 0
        """,
    ])
    func testPrivateOverrideReportsIncompatibleModifierPair(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.pairCode
                && $0.message == "modifier 'private' is incompatible with 'override'."
        }, "expected private×override pair diagnostic in \(diagnostics)")
        #expect(diagnostics.contains {
            $0.code == Self.pairCode
                && $0.message == "modifier 'override' is incompatible with 'private'."
        }, "expected override×private pair diagnostic in \(diagnostics)")
    }
}
#endif
