#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-ANNO-002: constructor / value-parameter / enum-entry annotation sema coverage
// Tests that @Target constraints are enforced on the four new usage sites:
//   primary constructor, secondary constructor, value parameter, enum entry.

extension AnnotationSemanticTests {

    // MARK: - Primary constructor annotations

    @Test func testConstructorOnlyAnnotationAcceptedOnPrimaryConstructor() {
        let source = """
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class CtorOnly

        class Foo @CtorOnly constructor()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.isEmpty,
            "Expected @Target(CONSTRUCTOR) annotation to be accepted on primary constructor, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testClassOnlyAnnotationRejectedOnPrimaryConstructor() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        class Bad @ClassOnly constructor()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.count == 1,
            "Expected @Target(CLASS) to be rejected on primary constructor, got: \(ctx.diagnostics.diagnostics)")
        #expect(diags.allSatisfy(isError))
    }

    // MARK: - Secondary constructor annotations

    @Test func testConstructorOnlyAnnotationAcceptedOnSecondaryConstructor() {
        let source = """
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class CtorOnly

        class Foo(val x: Int) {
            @CtorOnly
            constructor() : this(0)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.isEmpty,
            "Expected @Target(CONSTRUCTOR) annotation to be accepted on secondary constructor, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testFunctionOnlyAnnotationRejectedOnSecondaryConstructor() {
        let source = """
        @Target(AnnotationTarget.FUNCTION)
        annotation class FunOnly

        class Foo(val x: Int) {
            @FunOnly
            constructor() : this(0)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.count == 1,
            "Expected @Target(FUNCTION) to be rejected on secondary constructor, got: \(ctx.diagnostics.diagnostics)")
        #expect(diags.allSatisfy(isError))
    }

    // MARK: - Value parameter annotations

    @Test func testValueParameterOnlyAnnotationAcceptedOnFunctionParam() {
        let source = """
        @Target(AnnotationTarget.VALUE_PARAMETER)
        annotation class ParamOnly

        fun greet(@ParamOnly name: String) {}
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.isEmpty,
            "Expected @Target(VALUE_PARAMETER) to be accepted on function parameter, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testClassOnlyAnnotationRejectedOnFunctionParam() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        fun greet(@ClassOnly name: String) {}
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.count == 1,
            "Expected @Target(CLASS) to be rejected on function parameter, got: \(ctx.diagnostics.diagnostics)")
        #expect(diags.allSatisfy(isError))
    }

    @Test func testValueParameterOnlyAnnotationAcceptedOnPrimaryCtorParam() {
        let source = """
        @Target(AnnotationTarget.VALUE_PARAMETER)
        annotation class ParamOnly

        class Foo(@ParamOnly val x: Int)
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.isEmpty,
            "Expected @Target(VALUE_PARAMETER) to be accepted on primary ctor parameter, got: \(ctx.diagnostics.diagnostics)")
    }

    // MARK: - Enum entry annotations

    @Test func testFieldAnnotationAcceptedOnEnumEntry() {
        let source = """
        @Target(AnnotationTarget.FIELD)
        annotation class FieldMark

        enum class Color {
            @FieldMark RED,
            GREEN
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.isEmpty,
            "Expected @Target(FIELD) to be accepted on enum entry, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testFunctionOnlyAnnotationRejectedOnEnumEntry() {
        let source = """
        @Target(AnnotationTarget.FUNCTION)
        annotation class FunOnly

        enum class Color {
            @FunOnly RED,
            GREEN
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(diags.count == 1,
            "Expected @Target(FUNCTION) to be rejected on enum entry, got: \(ctx.diagnostics.diagnostics)")
        #expect(diags.allSatisfy(isError))
    }
}
#endif
