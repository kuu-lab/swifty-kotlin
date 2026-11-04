#if canImport(Testing)
import Foundation
import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

/// KUU-4119: an accessor's explicit visibility must fit the property's
/// visibility. kotlinc 2.4.20 rejects a getter whose visibility differs from
/// the property's at all (`GETTER_VISIBILITY_DIFFERS_FROM_PROPERTY_VISIBILITY`)
/// and a setter that is more permissive
/// (`SETTER_VISIBILITY_INCONSISTENT_WITH_PROPERTY_VISIBILITY`). `protected`
/// and `internal` are unordered relative to each other, so both directions of
/// that pairing are rejected. `private set`-style narrowing is legal for
/// setters only.
@Suite struct AccessorVisibilityTests {
    private static let getterMismatchCode = "KSWIFTK-SEMA-0476"
    private static let setterMismatchCode = "KSWIFTK-SEMA-0477"

    private func diagnose(_ source: String) throws -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            diagnostics = ctx.diagnostics.diagnostics
        }
        return diagnostics
    }

    @Test(arguments: [
        // private property: every mismatched getter visibility is rejected.
        "private var x: Int = 0\n    public get() = field",
        "private var x: Int = 0\n    internal get() = field",
        // internal property: wider and narrower getters are both rejected.
        "internal var x: Int = 0\n    public get() = field",
        "internal var x: Int = 0\n    private get() = field",
        // public property: narrower getters are still rejected.
        "var x: Int = 0\n    private get() = field",
        // `val` properties reject a mismatched getter the same way.
        "private val x: Int\n    public get() = 0",
        // Member properties follow the same rule.
        "open class C {\n    private var x: Int = 0\n        protected get() = field\n}",
        "open class C {\n    protected var x: Int = 0\n        internal get() = field\n}",
        "open class C {\n    protected val x: Int\n        private get() = 1\n}",
        "open class C {\n    var x: Int = 0\n        protected get() = field\n}",
        // Interface properties are implicitly public.
        "interface I {\n    val x: Int\n        private get() = 1\n}",
        // An `override` that repeats the inherited visibility on the getter
        // still differs once the declared visibility is narrower.
        "open class B { protected open val x: Int = 0 }\n"
            + "class C : B() {\n    override val x: Int\n        public get() = 1\n}",
    ])
    func testMismatchedGetterVisibilityIsRejected(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.getterMismatchCode
                && $0.message == "getter visibility must be the same as property visibility."
        }, "expected \(Self.getterMismatchCode) in \(diagnostics)")
    }

    @Test(arguments: [
        // private property: any wider setter visibility is rejected.
        "private var x: Int = 0\n    public set(value) { field = value }",
        "private var x: Int = 0\n    internal set(value) { field = value }",
        "open class C {\n    private var x: Int = 0\n        protected set\n}",
        // `protected`/`internal` are unordered: both directions are rejected.
        "open class C {\n    protected var x: Int = 0\n        internal set\n}",
        "open class C {\n    internal var x: Int = 0\n        protected set\n}",
        // internal property: a wider setter is rejected.
        "internal var x: Int = 0\n    public set(value) { field = value }",
        // An `override` of a protected property keeps that visibility, so an
        // `internal` setter is unordered with it and rejected.
        "open class B { protected open var x: Int = 0 }\n"
            + "class C : B() {\n    override var x: Int = 1\n        internal set\n}",
    ])
    func testMorePermissiveSetterVisibilityIsRejected(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(diagnostics.contains {
            $0.code == Self.setterMismatchCode
                && $0.message == "setter visibility cannot be more permissive than property visibility."
        }, "expected \(Self.setterMismatchCode) in \(diagnostics)")
    }

    @Test func testBothAccessorsReportTheirOwnDiagnostic() throws {
        let diagnostics = try diagnose("""
        private var x: Int = 0
            public get() = field
            public set(value) { field = value }
        """)
        #expect(diagnostics.contains { $0.code == Self.getterMismatchCode },
                "expected \(Self.getterMismatchCode) in \(diagnostics)")
        #expect(diagnostics.contains { $0.code == Self.setterMismatchCode },
                "expected \(Self.setterMismatchCode) in \(diagnostics)")
    }

    @Test(arguments: [
        // Narrower setter visibility is legal on any property visibility.
        "var x: Int = 0\n    private set",
        "var x: Int = 0\n    internal set",
        "internal var x: Int = 0\n    private set",
        "open class C {\n    var x: Int = 0\n        protected set\n}",
        "open class C {\n    protected var x: Int = 0\n        private set\n}",
        // Accessors spelling the property's own visibility are legal.
        "private var x: Int = 0\n    private get() = field\n    private set(value) { field = value }",
        "var x: Int = 0\n    public get() = field",
        "private val x: Int\n    private get() = 0",
        "open class C {\n    protected var x: Int = 0\n        protected set\n}",
        "internal var x: Int = 0\n    internal set(value) { field = value }",
        // Unmodified accessors inherit the property visibility.
        "var x: Int = 0\n    get() = field\n    set(value) { field = value }",
        "val x: Int\n    get() = 1",
        // An `override` without a visibility modifier inherits the overridden
        // member's visibility, so matching accessors stay legal.
        "open class B { protected open val x: Int = 0 }\n"
            + "class C : B() {\n    override val x: Int\n        protected get() = 1\n}",
        "open class B { protected open var x: Int = 0 }\n"
            + "class C : B() {\n    override var x: Int = 1\n        protected set\n}",
        "open class B { internal open var x: Int = 0 }\n"
            + "class C : B() {\n    override var x: Int = 1\n        internal set\n}",
    ])
    func testLegalAccessorVisibilityIsAccepted(source: String) throws {
        let diagnostics = try diagnose(source)
        #expect(!diagnostics.contains {
            $0.code == Self.getterMismatchCode || $0.code == Self.setterMismatchCode
        }, "unexpected accessor visibility diagnostic in \(diagnostics)")
        #expect(!diagnostics.contains { $0.severity == .error },
                "expected no errors in \(diagnostics)")
    }
}
#endif
