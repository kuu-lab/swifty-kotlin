@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3948: constructor-delegation arguments (`: this(...)`, `: super(...)`)
/// and supertype-constructor arguments in the class header / object
/// declaration evaluate before the instance exists, so reading or writing a
/// member of the class being constructed reports `KSWIFTK-SEMA-0058`
/// ("cannot access '<this>' before the instance has been initialized"),
/// matching kotlinc — regardless of member initialization order.
///
/// Explicit `this.` receivers, member-function calls, and inherited members
/// in the same positions are already rejected during type checking with other
/// codes (SEMA-0051 / SEMA-0002 / SEMA-0022); the unqualified member read was
/// the silent path.
@Suite
struct SecondaryConstructorThisReadTests {
    static let rejected = [
        // `this` delegation reading an own member.
        "class Box { val value = 1; constructor(a: Int) { }; constructor() : this(TARGET) }",
        "class Box(val p: Int) { val value = 1; constructor() : this(TARGET) }",
        // Even a member declared before the constructor is unreachable —
        // `this` itself does not exist yet.
        "class Box { constructor(a: Int) { }; val value = 1; constructor() : this(TARGET) }",
        // `super` delegation reading an own member.
        "open class Base(val a: Int); class Box : Base { val value = 1; constructor() : super(TARGET) }",
        // Supertype-constructor arguments in the class header.
        "open class Base(val a: Int); class Box : Base(TARGET) { val value = 1 }",
        // The read may be nested inside an argument expression.
        "class Box { val value = 1; constructor(a: Int) { }; constructor() : this(TARGET + 1) }",
        "class Box { val value = 1; constructor(a: Int) { }; constructor() : this(a = TARGET) }",
        "class Box { val value = 1; constructor(a: String) { }; constructor() : this(\"${TARGET}\") }",
        // Member access chained on an own member read.
        "class Box { val inner = Inner(); val value = 1; constructor(a: Int) { }; constructor() : this(TARGET.x) }; class Inner { val x = 4 }",
    ]

    static let accepted = [
        // Literals, parameters, and top-level or other-instance values.
        "class Box { val value = 1; constructor(a: Int) { }; constructor() : this(3) }",
        "class Box { val value = 1; constructor(a: Int) { }; constructor(q: Int) : this(q) }",
        "open class Base(val a: Int); class Box : Base { val value = 1; constructor(q: Int) : super(q) }",
        "val top = 1; class Box { val value = 1; constructor(a: Int) { }; constructor() : this(top) }",
        // Members of another instance are not this instance's `this`.
        "class Box { val value = 1; constructor(a: Int) { }; constructor() : this(other.value) }; val other = Box(2)",
        // Companion-object members do not need the instance.
        "class Box { constructor(a: Int) { }; constructor() : this(c); companion object { val c = 1 } }",
        // A stored lambda runs after construction, so it may read members.
        "class Box { val value = 1; constructor(a: () -> Int) { }; constructor() : this({ TARGET }) }",
        // An `inner` class may read members of its captured outer `this`.
        "open class Base(val a: Int); open class Outer { val o = 1; inner class Inner : Base { constructor() : super(o) } }",
        // Primary-constructor parameters are values, not members, in the
        // supertype-constructor argument scope.
        "open class Base(val a: Int); class Box(val p: Int) : Base(p) { val value = 1 }",
    ]

    @Test(arguments: rejected)
    func rejectsThisReadBeforeInstanceExists(source: String) throws {
        try check(
            source.replacingOccurrences(of: "TARGET", with: "value"),
            expectedThisAccessErrors: 1
        )
    }

    @Test(arguments: accepted)
    func acceptsNonThisValues(source: String) throws {
        try check(
            source.replacingOccurrences(of: "TARGET", with: "value"),
            expectedThisAccessErrors: 0
        )
    }

    private func check(_ source: String, expectedThisAccessErrors: Int) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0058" }.count == expectedThisAccessErrors,
                "\(source): \(errors)"
            )
            if expectedThisAccessErrors == 0 { #expect(errors.isEmpty, "\(source): \(errors)") }
        }
    }
}
