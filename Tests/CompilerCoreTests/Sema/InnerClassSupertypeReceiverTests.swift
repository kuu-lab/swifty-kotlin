#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// KUU-3236: an inner class used as a supertype requires an implicit receiver
// of its containing class. kotlinc rejects contexts where no such receiver is
// reachable ("constructor of the inner class ... can only be called with a
// receiver of the containing class"), and reports a distinct diagnostic when a
// non-inner boundary blocks an otherwise matching outer class ("outer class
// 'X' of non-inner class cannot be used as receiver").

@Suite
struct InnerClassSupertypeReceiverTests {
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

    @Test func topLevelClassExtendingInnerClassIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class C : Outer.I()
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0439"],
                    "Expected the missing-receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func nonInnerNestedClassCannotUseOuterAsReceiver() throws {
        try withSemaContext("""
        open class Outer { open inner class I
            class N : I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0440"],
                    "Expected the non-inner receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func innerClassInsideOuterMayExtendSiblingInner() throws {
        try withSemaContext("""
        open class Outer { open inner class I
            inner class C : I()
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected an inner class to capture the enclosing receiver, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func innerClassInSubclassOfOuterIsAccepted() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class Sub : Outer() {
            inner class C : I()
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected the subclass receiver to satisfy the inner constructor, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func nonInnerClassInSubclassCannotUseSubclassAsReceiver() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class Sub : Outer() {
            class C : Outer.I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0440"],
                    "Expected the non-inner receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func innerClassInsideNonInnerMemberOfSubclassIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class Sub : Outer() {
            class M {
                inner class C : Outer.I()
            }
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0440"],
                    "Expected the non-inner boundary diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func deeplyNestedInnerChainIsAccepted() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class Sub : Outer() {
            inner class M {
                inner class C : I()
            }
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected the inner chain to reach the subclass receiver, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func unrelatedEnclosingClassIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class Unrelated {
            class C : Outer.I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0439"],
                    "Expected the missing-receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func companionObjectCannotUseOuterAsReceiver() throws {
        try withSemaContext("""
        open class Outer { open inner class I
            companion object : I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0439"],
                    "Expected the missing-receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func localClassInTopLevelFunctionIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        fun f() {
            class L : Outer.I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0439"],
                    "Expected the missing-receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func localClassInMemberFunctionIsAccepted() throws {
        try withSemaContext("""
        open class Outer { open inner class I
            fun f() {
                class L : I()
            }
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected the member-function receiver to satisfy the inner constructor, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func anonymousObjectInTopLevelFunctionIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        fun f() {
            object : Outer.I() { }
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0439"],
                    "Expected the missing-receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func anonymousObjectInMemberFunctionIsAccepted() throws {
        try withSemaContext("""
        open class Outer { open inner class I
            fun f() {
                object : I() { }
            }
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected the member-function receiver to satisfy the inner constructor, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func anonymousObjectInInnerSuperConstructorArgumentIsAccepted() throws {
        try withSemaContext("""
        open class Base(val x: Any)
        open class Outer { open inner class I
            inner class Nested : Base(object : Outer.I() { })
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected the enclosing receiver to satisfy the inner constructor, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func anonymousObjectInNonInnerSuperConstructorArgumentIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        open class Base(val x: Any)
        class Sub : Outer() {
            class M : Base(object : Outer.I() { })
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0440"],
                    "Expected the non-inner receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func localClassInExtensionFunctionIsAccepted() throws {
        // kotlinc requires the qualified name here: an extension receiver is
        // an implicit receiver, not a lexical classifier scope, so a bare `I`
        // is unresolved even though `Outer.I()` is accepted and the extension
        // receiver satisfies the inner class's enclosing-instance requirement.
        try withSemaContext("""
        open class Outer { open inner class I }
        fun Outer.extSub() {
            class L : Outer.I()
        }
        """) { ctx in
            #expect(!ctx.diagnostics.hasError,
                    "Expected the extension receiver to satisfy the inner constructor, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func localClassInExtensionFunctionUnqualifiedInnerNameIsRejected() throws {
        // kotlinc: "unresolved reference 'I'" — member classifiers are not
        // reachable by bare name through an extension receiver.
        try withSemaContext("""
        open class Outer { open inner class I }
        fun Outer.extSub() {
            class L : I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0025"],
                    "Expected the unresolved-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func localClassInUnrelatedExtensionFunctionIsRejected() throws {
        try withSemaContext("""
        open class Outer { open inner class I }
        class Other
        fun Other.extSub() {
            class L : Outer.I()
        }
        """) { ctx in
            #expect(errorCodes(ctx) == ["KSWIFTK-SEMA-0439"],
                    "Expected the missing-receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
