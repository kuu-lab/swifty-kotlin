@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ValPropertyInitializationTests {
    // Keep these source strings directly usable by the Kotlin 2.3.10 oracle.
    static let accepted = [
        "class Box { val value: Int; init { TARGET = 1 } }",
        "class Box(flag: Boolean) { val value: Int; init { if (flag) TARGET = 1 else TARGET = 2 } }",
        "class Box(flag: Boolean) { val value: Int; init { if (flag) { TARGET = 1 } else { TARGET = 2 } } }",
        "class Box(flag: Boolean) { val value: Int; init { when (flag) { true -> TARGET = 1; false -> TARGET = 2 } } }",
        "class Box(flag: Boolean) { val value: Int; init { when { flag -> TARGET = 1; else -> TARGET = 2 } } }",
        "class Box { val value: Int; init { val x = 1 }; init { TARGET = 2 } }",
        "class Box { val value: Int; constructor() { TARGET = 1 } }",
        "class Box { val value: Int; constructor(flag: Boolean) { if (flag) TARGET = 1 else TARGET = 2 } }",
        "class Box { val value: Int; constructor() { TARGET = 1 }; constructor(x: Int) { TARGET = x } }",
        "class Box { val value: Int; constructor() : this(1) {}; constructor(x: Int) { TARGET = x } }",
        "class Box { val value: Int; constructor(x: Int) { TARGET = x }; constructor() : this(1) {} }",
        "class Box { val value: Int; init { TARGET = 1 }; constructor() {} }",
        "open class Base; class Box : Base { val value: Int; constructor() : super() { TARGET = 1 } }",
        "class Box() { val value: Int; init { TARGET = 1 }; constructor(x: Int) : this() {} }",
        "class Box { var value: Int = 0; init { TARGET = 1; TARGET = 2 }; constructor() { TARGET = 3 } }",
        "class Box { val value: Int; val other: Int; init { TARGET = 1; this.other = 2 } }",
        "class Box { val value: Int = 0; init { var value = 1; value = 2 } }",
        "class Box(flag: Boolean, failure: Throwable) { val value: Int; init { if (flag) { TARGET = 1; throw failure }; TARGET = 2 } }",
        "class Box { val value: Int; constructor(flag: Boolean) { if (flag) { TARGET = 1; return }; TARGET = 2 } }",
        "class Box { val value: Int; init { while (true) { TARGET = 1; break } } }",
        "class Box { val value: Int; init { do { TARGET = 1 } while (false) } }",
        "class Box { val value: Int; init { outer@ while (true) { while (true) { TARGET = 1; break@outer }; TARGET = 2 } } }",
        "class Box { val value: Int; init { try {} finally { TARGET = 1 } } }",
        "class Box { val value: Int; init { while (false) { TARGET = 1 }; TARGET = 2 } }",
        "class Box { val value: Int get() = field; init { TARGET = 1 } }",
        "class Box { val value: Int; init { var x = 0; val f = { x = 1 }; TARGET = x } }",
        "fun make() { class Box { val value: Int; init { TARGET = 1 } } }",
        "object Box { val value: Int; init { TARGET = 1 } }",
    ]

    static let rejected = [
        "class Box { val value: Int = 0; init { TARGET = 2 } }",
        "class Box { val value: Int; init { TARGET = 1; TARGET = 2 } }",
        "class Box { val value: Int; init { TARGET = 1 }; init { TARGET = 2 } }",
        "class Box(val value: Int) { init { TARGET = 2 } }",
        "class Box(flag: Boolean) { val value: Int; init { if (flag) TARGET = 1; TARGET = 2 } }",
        "class Box(flag: Boolean) { val value: Int; init { if (flag) TARGET = 1 else TARGET = 2; TARGET = 3 } }",
        "class Box(flag: Boolean) { val value: Int; init { if (flag) { TARGET = 1; TARGET = 2 } else TARGET = 3 } }",
        "class Box(flag: Boolean) { val value: Int; init { when (flag) { true -> TARGET = 1; false -> TARGET = 2 }; TARGET = 3 } }",
        "class Box(flag: Boolean) { val value: Int; init { if (flag) TARGET = 1 }; init { TARGET = 2 } }",
        "class Box { val value: Int = 0; constructor() { TARGET = 1 } }",
        "class Box { val value: Int; constructor() { TARGET = 1; TARGET = 2 } }",
        "class Box { val value: Int; init { TARGET = 1 }; constructor() { TARGET = 2 } }",
        "class Box() { val value: Int; init { TARGET = 1 }; constructor(x: Int) : this() { TARGET = x } }",
        "class Box { val value: Int; constructor() : this(1) { TARGET = 2 }; constructor(x: Int) { TARGET = x } }",
        "class Box { val value: Int; constructor(x: Int) { TARGET = x }; constructor() : this(1) { TARGET = 2 } }",
        "class Box { val value: Int; constructor() : this(1) { TARGET = 2 }; constructor(x: Int) : this(x, true) {}; constructor(x: Int, flag: Boolean) { TARGET = x } }",
        "class Box { val value: Int; constructor() : this(true) { TARGET = 2 }; constructor(flag: Boolean) { if (flag) { TARGET = 1; return }; TARGET = 2 } }",
        "class Box(flag: Boolean) { val value: Int; init { while (flag) { TARGET = 1 } } }",
        "class Box(flag: Boolean) { val value: Int; init { do { TARGET = 1 } while (flag) } }",
        "class Box(flag: Boolean) { val value: Int; init { while (flag) { TARGET = 1; break }; TARGET = 2 } }",
        "class Box { val value: Int; init { try { TARGET = 1 } finally { TARGET = 2 } } }",
        "class Box { val value: Int; init { try { TARGET = 1 } catch (e: Throwable) { TARGET = 2 } } }",
        "class Box { val value: Int; init { val f = { TARGET = 1 }; TARGET = 2 } }",
        "class Box { val value: Int; init { fun f() { TARGET = 1 }; TARGET = 2 } }",
        "fun make() { class Box { val value: Int; init { TARGET = 1; TARGET = 2 } } }",
        "class Box { val value: Int; constructor() { TARGET = 1; return; TARGET = 2 } }",
        "class Box(failure: Throwable) { val value: Int = 0; init { throw failure; TARGET = 1 } }",
        "class Box { val value: Int = 0; init { while (false) { TARGET = 1 } } }",
        "class Box { val value: Int get() = 0; init { TARGET = 1 } }",
        "class Box { init { TARGET = 1 }; val value: Int = 2 }",
        "class Box { val value: Int; init { value = 1; this.value = 2 } }",
        "object Box { val value: Int = 0; init { TARGET = 1 } }",
        "fun make() = object { val value: Int; init { value = 1; this.value = 2 } }",
        "class Box { val value: Int get() { val field = 0; return field }; init { TARGET = 1 } }",
    ]

    @Test(arguments: accepted, ["value", "this.value", "this@Box.value"])
    func acceptsInitialization(source: String, target: String) throws {
        try check(source.replacingOccurrences(of: "TARGET", with: target), rejects: false)
    }

    @Test(arguments: rejected, ["value", "this.value", "this@Box.value"])
    func rejectsReassignment(source: String, target: String) throws {
        try check(source.replacingOccurrences(of: "TARGET", with: target), rejects: true)
    }

    @Test
    func nestedLoopsWithoutFieldWritesDoNotRevisitEveryPath() throws {
        var body = ""
        for _ in 0 ..< 22 { body = "while (flag) { \(body) }" }
        try check("class Box(flag: Boolean) { val value: Int = 0; init { \(body) } }", rejects: false)
    }

    @Test
    func nestedFinallyWithoutFieldWritesReusesEquivalentStates() throws {
        var body = ""
        for _ in 0 ..< 22 { body = "try { if (flag) throw failure } finally { \(body) }" }
        try check("class Box(flag: Boolean, failure: Throwable) { val value: Int = 0; init { \(body) } }", rejects: false)
    }

    private func check(_ source: String, rejects: Bool) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            if rejects {
                #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0014" }, "\(source): \(errors)")
                #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0014" || $0.code == "KSWIFTK-SEMA-0424" }, "\(source): \(errors)")
            } else {
                #expect(errors.isEmpty, "\(source): \(errors)")
            }
        }
    }
}
