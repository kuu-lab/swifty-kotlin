#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// KUU-3250: supertypes that fail to resolve must not be dropped silently.
// kotlinc reports `unresolved reference` for names that match nothing, so
// KSwiftK emits KSWIFTK-SEMA-0025 on the declaring nominal. Resolution also
// covers classifiers inherited through an enclosing class's supertypes
// (member types are visible by simple name inside the class body) and
// type-use annotations wrapping the supertype.

@Suite
struct UnresolvedSupertypeDiagnosticTests {
    private func withSemaContext(
        _ source: String,
        body: (CompilationContext) throws -> Void
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            try body(ctx)
        }
    }

    private func errorCodes(_ ctx: CompilationContext) -> [String] {
        ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
    }

    @Test func unresolvableSuperclassIsReported() throws {
        try withSemaContext("""
        class C : NonExistent()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableQualifiedSupertypeReportsRoot() throws {
        try withSemaContext("""
        class C : NotExist.Nested()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableQualifiedSupertypeReportsMissingTail() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class C : Outer.Missing()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableInterfaceSupertypeIsReported() throws {
        try withSemaContext("""
        interface J : NotExist
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableObjectSupertypeIsReported() throws {
        try withSemaContext("""
        object O : NotExist()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableEnumSupertypeIsReported() throws {
        try withSemaContext("""
        enum class E : NotExist { A }
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func annotatedUnresolvableSupertypeIsReported() throws {
        try withSemaContext("""
        @Target(AnnotationTarget.TYPE)
        annotation class Anno
        class C : @Anno NotExist()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableSupertypeTypeArgumentIsReported() throws {
        try withSemaContext("""
        class Box<T>
        class C : Box<NotExist>()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unresolvableDelegationSupertypeIsReported() throws {
        try withSemaContext("""
        interface A
        class Z(a: A) : A by a, NotExist
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func localClassWithUnresolvableSupertypeIsReported() throws {
        try withSemaContext("""
        fun f() {
            class C : NonExistent()
        }
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func typeParameterSupertypeDoesNotReportUnresolvedName() throws {
        // `T` resolves to the type parameter; kotlinc rejects it under a
        // different diagnostic ("supertype is not a class or interface"), so
        // no unresolved-name report may fire for the resolved name.
        try withSemaContext("""
        class C<T> : T()
        """) { ctx in
            #expect(!errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Unexpected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func typeParameterQualifiedSupertypeReportsMissingTail() throws {
        try withSemaContext("""
        class C<T> : T.Nested()
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Expected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func annotatedResolvableSupertypeBindsInheritedMembers() throws {
        // `@Anno Base()` previously dropped the edge entirely; member access
        // on the subtype proves the edge is bound.
        try withSemaContext("""
        @Target(AnnotationTarget.TYPE)
        annotation class Anno
        open class Base { fun f() = 42 }
        class C : @Anno Base()
        fun use(c: C) = c.f()
        """) { ctx in
            #expect(errorCodes(ctx).isEmpty,
                    "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func inheritedMemberClassifierResolvesAsSupertype() throws {
        // `I` inside `Sub.M` names `Outer.I` through `Sub`'s inherited member
        // scope; the bound edge makes `C` assignable to `I`.
        try withSemaContext("""
        open class Outer { open inner class I }
        class Sub : Outer() {
            class M {
                inner class C : I()
                fun asI(c: C): I = c
            }
        }
        """) { ctx in
            #expect(errorCodes(ctx).isEmpty,
                    "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func inheritedMemberClassifierResolvesInTypePositions() throws {
        try withSemaContext("""
        open class Outer { interface I }
        class Sub : Outer() {
            class M { fun f(i: I): I = i }
        }
        """) { ctx in
            #expect(errorCodes(ctx).isEmpty,
                    "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func typealiasSupertypeStillBinds() throws {
        try withSemaContext("""
        open class Base { fun f() = 1 }
        typealias TB = Base
        class C : TB()
        fun use(c: C) = c.f()
        """) { ctx in
            #expect(errorCodes(ctx).isEmpty,
                    "Expected no errors, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func duplicateSupertypeIsRejected() throws {
        // KUU-3120: kotlinc reports "a supertype appears twice" when the same
        // resolved classifier is listed more than once.
        try withSemaContext("""
        interface I
        class C : I, I
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0440"),
                    "Expected KSWIFTK-SEMA-0440, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func duplicateInterfaceSupertypeIsRejected() throws {
        try withSemaContext("""
        interface I
        interface J : I, I
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0440"),
                    "Expected KSWIFTK-SEMA-0440, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func duplicateSupertypeThroughTypealiasIsRejected() throws {
        try withSemaContext("""
        interface I
        typealias TI = I
        class C : I, TI
        """) { ctx in
            #expect(errorCodes(ctx).contains("KSWIFTK-SEMA-0440"),
                    "Expected KSWIFTK-SEMA-0440, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func distinctSupertypesStayLegal() throws {
        try withSemaContext("""
        interface A
        interface B
        open class Base
        class C : Base(), A, B
        """) { ctx in
            #expect(!errorCodes(ctx).contains("KSWIFTK-SEMA-0440"),
                    "Unexpected KSWIFTK-SEMA-0440, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func qualifiedNestedSupertypeStillResolves() throws {
        try withSemaContext("""
        open class Outer { open class Nested }
        class C : Outer.Nested()
        """) { ctx in
            #expect(!errorCodes(ctx).contains("KSWIFTK-SEMA-0025"),
                    "Unexpected KSWIFTK-SEMA-0025, got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
