@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DefinitePropertyInitializationTests {
    // Keep the matrix directly reusable with the Kotlin 2.3.10 oracle.
    static let accepted = [
        "class Box { constructor() { TARGET = 1 }; KIND value: Int }",
        "class Box { KIND value: Int; constructor() { try { return } finally { TARGET = 1 } } }",
        "class Box { KIND value: Int; constructor() { outer@ while (true) { while (true) { TARGET = 1; break@outer } } } }",
        "class Box { KIND value: Int; constructor() { TARGET = 1 } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { if (flag) TARGET = 1 else TARGET = 2 } }",
        "class Box { KIND value: Int; constructor() : this(1) {}; constructor(x: Int) { TARGET = x } }",
        "class Box { KIND value: Int; constructor(x: Int) { TARGET = x }; constructor() : this(1) {} }",
        "class Box { KIND value: Int; init { TARGET = 1 }; constructor() {} }",
        "class Box { KIND value: Int; init { val x = 1 }; init { TARGET = 2 }; constructor() {} }",
        "class Box() { KIND value: Int; init { TARGET = 1 }; constructor(x: Int) : this() {} }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { if (flag) { TARGET = 1; return }; TARGET = 2 } }",
        "class Box { KIND value: Int; constructor(flag: Boolean, failure: Throwable) { if (flag) throw failure; TARGET = 2 } }",
        "class Box { KIND value: Int; constructor() { while (true) { TARGET = 1; break } } }",
        "class Box { KIND value: Int; constructor() { do { TARGET = 1 } while (false) } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { when (flag) { true -> TARGET = 1; false -> TARGET = 2 } } }",
        "class Box { KIND value: Int; constructor() { try {} finally { TARGET = 1 } } }",
        "class Box { KIND value: Int; constructor(flag: Boolean, failure: Throwable) { try { if (flag) throw failure; TARGET = 1 } catch (e: Throwable) { throw e } } }",
        "class Box { KIND value: Int; constructor(flag: Boolean, failure: Throwable) { try { if (flag) throw failure } catch (e: Throwable) {} finally { TARGET = 1 } } }",
        "abstract class Box { KIND value: Int; constructor() { TARGET = 1 } }",
        "object Box { KIND value: Int; init { TARGET = 1 } }",
        "fun make() { class Box { KIND value: Int; constructor() { TARGET = 1 } } }",
    ]

    static let rejected = [
        "class Box { KIND value: Int; init { TARGET = 1 }; constructor(failure: Throwable) { throw failure } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { outer@ while (true) { if (flag) break@outer; TARGET = 1; break@outer } } }",
        "class Box { KIND value: Int; constructor(failure: Throwable) { throw failure } }",
        "class Box { KIND value: Int; constructor(failure: Throwable) { TARGET = 1; throw failure } }",
        "class Box { KIND value: Int; constructor(failure: Throwable) { throw failure }; constructor() { TARGET = 1 } }",
        "class Box { KIND value: Int; constructor() { while (true) {} } }",
        "class Box { KIND value: Int; constructor() { try { TARGET = 1 } finally { while (true) {} } } }",
        "class Box { KIND value: Int; constructor() {} }",
        "class Box { KIND value: Int; init {} }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { if (flag) TARGET = 1 } }",
        "class Box { KIND value: Int; constructor() { TARGET = 1 }; constructor(x: Int) {} }",
        "class Box { KIND value: Int; constructor() : this(1) {}; constructor(x: Int) {} }",
        "class Box() { KIND value: Int; constructor(x: Int) : this() { TARGET = x } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { if (flag) return; TARGET = 1 } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { while (flag) { TARGET = 1; break } } }",
        "class Box { KIND value: Int; constructor() { while (false) { TARGET = 1 } } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { do { if (flag) break; TARGET = 1 } while (false) } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { when { flag -> TARGET = 1 } } }",
        "class Box { KIND value: Int; constructor(flag: Boolean, failure: Throwable) { try { if (flag) throw failure; TARGET = 1 } catch (e: Throwable) {} } }",
        "class Box { KIND value: Int; constructor(flag: Boolean) { try {} finally { if (flag) TARGET = 1 } } }",
        "class Box { KIND value: Int; constructor() { val f = { TARGET = 1 } } }",
        "abstract class Box { KIND value: Int; constructor() {} }",
        "object Box { KIND value: Int; init {} }",
        "fun make() { class Box { KIND value: Int; constructor() {} } }",
    ]

    static let variants = ["val", "var"].flatMap { kind in
        ["value", "this.value", "this@Box.value"].map { "\(kind):\($0)" }
    }

    @Test(arguments: accepted, variants)
    func acceptsEveryNormalExit(source: String, variant: String) throws {
        try check(source.replacingOccurrences(of: "KIND", with: variant.hasPrefix("val:") ? "val" : "var").replacingOccurrences(of: "TARGET", with: String(variant.split(separator: ":", maxSplits: 1)[1])), missing: 0)
    }

    @Test(arguments: rejected, variants)
    func rejectsMissingNormalExit(source: String, variant: String) throws {
        try check(source.replacingOccurrences(of: "KIND", with: variant.hasPrefix("val:") ? "val" : "var").replacingOccurrences(of: "TARGET", with: String(variant.split(separator: ":", maxSplits: 1)[1])), missing: 1)
    }

    @Test
    func laterPropertiesAreNotRequiredWhenClassInitializationCannotComplete() throws {
        try check("""
        fun TODO(): Nothing = TODO()
        class C {
            val todo: String = TODO()
            val uninitializedVal: String
            var uninitializedVar: String
        }
        class Foo {
            init { TODO() }
            val uninitializedVal: String
            var uninitializedVar: String
        }
        class Bar {
            val initializedVal = 43
            init { TODO() }
            val uninitializedVal: String
            var uninitializedVar: String
        }
        class ThrowingInit(failure: Throwable) {
            init { throw failure }
            val uninitializedVal: String
        }
        """, missing: 0)

        try check("""
        fun TODO(): Nothing = TODO()
        class SometimesCompletes(flag: Boolean) {
            init { if (flag) TODO() }
            val uninitialized: String
        }
        """, missing: 1)

        try check("""
        class NormallyCompletingInitializer {
            val initialized = 43
            val uninitialized: String
        }
        """, missing: 1)

        try check("""
        class SecondaryConstructorThatThrows {
            val uninitialized: Int
            constructor(failure: Throwable) { throw failure }
        }
        """, missing: 1)
    }

    @Test
    func fieldAnnotationsDoNotSuppressMissingInitialization() throws {
        try check("""
        @Target(AnnotationTarget.FIELD)
        annotation class FieldMark
        class EmptyConstructor {
            @FieldMark val immutable: Int
            @field:FieldMark var mutable: Int
            constructor() {}
        }
        class UnmarkedEmptyConstructor {
            val immutable: Int
            var mutable: Int
            constructor() {}
        }
        """, missing: 4)
    }

    @Test
    func excludesLateinitAbstractAndFieldlessProperties() throws {
        try check("""
        abstract class Box {
            abstract val abstractValue: Int
            lateinit var deferred: String
            val computed: Int get() = 1
            var computedMutable: Int
                get() = 1
                set(value) {}
            constructor() {}
        }
        """, missing: 0)
    }

    @Test
    func typeUseAnnotationPlacementDoesNotHideComputedGetterBodies() throws {
        try check("""
        @Target(AnnotationTarget.TYPE)
        annotation class TypeAnn(val name: String)

        class MixedPlacement {
            val getterAnnotated: Int
                get(): @TypeAnn("1") Int = 123
            val propertyAnnotated: @TypeAnn("1") Int
                get(): Int = 123
        }

        class GetterPlacementControl {
            val first: Int
                get(): @TypeAnn("1") Int = 123
            val second: Int
                get(): @TypeAnn("1") Int = 123
        }

        class PropertyPlacementControl {
            val first: @TypeAnn("1") Int
                get(): Int = 123
            val second: @TypeAnn("1") Int
                get(): Int = 123
        }

        class GetterPlacementAlone {
            val value: Int
                get(): @TypeAnn("1") Int = 123
        }

        class PropertyPlacementAlone {
            val value: @TypeAnn("1") Int
                get(): Int = 123
        }
        """, missing: 0)
        try check("class Stored { val uninitialized: Int }", missing: 1)
    }

    @Test
    func defaultAccessorAndBackingFieldStillRequireInitialization() throws {
        try check("""
        class Box {
            val immutable: Int get() = field
            var mutable: Int
                get() = 1
            constructor() {}
        }
        """, missing: 2)
    }

    @Test
    func customSetterDoesNotProveBackingFieldInitialization() throws {
        try check("class Box { var value: Int; set(v) { field = v }; constructor() { value = 1 } }", missing: 1)
    }

    @Test
    func assignmentToAnotherInstanceDoesNotInitializeThisInstance() throws {
        try check("class Box { var value: Int; constructor(other: Box) { other.value = 1 } }", missing: 1)
    }

    private func check(_ source: String, missing: Int) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0424" }.count == missing, "\(source): \(errors)")
            if missing == 0 { #expect(errors.isEmpty, "\(source): \(errors)") }
        }
    }
}
