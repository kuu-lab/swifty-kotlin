#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-ANNO-002: annotation sema / diagnostics coverage
// Covers: @Target enforcement on additional sites, @Retention(RUNTIME) metadata,
// @Repeatable allows multiple occurrences, @MustBeDocumented on annotation class,
// annotation class without @Target is unrestricted, getter/setter use-site targets,
// file-level @Target(FILE) acceptance, object/enum class targets,
// annotation with default params (no-arg call is valid),
// annotation class with named vs positional arg acceptance.

extension AnnotationSemanticTests {

    // MARK: - @Target enforcement on additional sites

    @Test func testTargetFunctionOnlyRejectsProperty() {
        let source = """
        @Target(AnnotationTarget.FUNCTION)
        annotation class FunctionOnly

        @FunctionOnly
        val bad: Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.count == 1, "Expected one annotation-target diagnostic for property, got: \(ctx.diagnostics.diagnostics)")
        let v0 = diags.allSatisfy(isError)
        #expect(v0, "Annotation-target diagnostics should be errors")
    }

    @Test func testTargetPropertyOnlyAcceptsProperty() {
        let source = """
        @Target(AnnotationTarget.PROPERTY)
        annotation class PropOnly

        @PropOnly
        val fine: Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no annotation-target diagnostics for property, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTargetPropertyOnlyRejectsClass() {
        let source = """
        @Target(AnnotationTarget.PROPERTY)
        annotation class PropOnly

        @PropOnly
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.count == 1, "Expected one annotation-target diagnostic for class, got: \(ctx.diagnostics.diagnostics)")
        let v1 = diags.allSatisfy(isError)
        #expect(v1, "Annotation-target diagnostics should be errors")
    }

    @Test func testAnnotationClassWithoutTargetIsUnrestricted() {
        // An annotation class with no @Target at all can be applied to any site.
        let source = """
        annotation class Anywhere

        @Anywhere
        class OnClass

        @Anywhere
        fun onFunction() {}

        @Anywhere
        val onProperty: Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no annotation-target errors for annotation without @Target, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTargetClassAndFunctionRejectsBothWhenWrong() {
        let source = """
        @Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
        annotation class ClassOrFunction

        @ClassOrFunction
        class Fine

        @ClassOrFunction
        fun alsoFine() {}

        @ClassOrFunction
        val bad: Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.count == 1, "Expected exactly one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        let v2 = diags.allSatisfy(isError)
        #expect(v2, "Annotation-target diagnostics should be errors")
    }

    @Test func testTargetTypeAliasAcceptsTypeAliasDeclaration() {
        let source = """
        @Target(AnnotationTarget.TYPEALIAS)
        annotation class TypeAliasOnly

        @TypeAliasOnly
        typealias UserName = String
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no annotation-target diagnostics for typealias, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTargetClassRejectsTypeAliasDeclaration() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        @ClassOnly
        typealias UserName = String
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.count == 1, "Expected one annotation-target diagnostic for typealias, got: \(ctx.diagnostics.diagnostics)")
        let v3 = diags.allSatisfy(isError)
        #expect(v3, "Annotation-target diagnostics should be errors")
        #expect(
            diags.first?.message.contains("type alias") == true,
            "Expected diagnostic to mention type alias usage, got: \(diags.map(\.message))"
        )
    }

    // MARK: - @Retention(RUNTIME) metadata

    @Test func testRetentionRuntimeIsRecordedOnAnnotationSymbol() throws {
        let source = """
        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeAnnotation
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbolID = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("RuntimeAnnotation")]))
        let annotations = sema.symbols.annotations(for: symbolID)

        let v4 = annotations.contains(where: {
            $0.annotationFQName.hasSuffix("Retention")
                && $0.arguments.contains(where: { $0.contains("RUNTIME") })
        })
        #expect(
            v4,
            "Expected @Retention(RUNTIME) to be recorded on annotation symbol, got: \(annotations)"
        )
    }

    @Test func testRetentionSourceAnnotationIsRecorded() throws {
        let source = """
        @Retention(AnnotationRetention.SOURCE)
        annotation class SourceOnly
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbolID = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("SourceOnly")]))
        let annotations = sema.symbols.annotations(for: symbolID)

        let v5 = annotations.contains(where: {
            $0.annotationFQName.hasSuffix("Retention")
                && $0.arguments.contains(where: { $0.contains("SOURCE") })
        })
        #expect(
            v5,
            "Expected @Retention(SOURCE) to be recorded on annotation symbol, got: \(annotations)"
        )
    }

    // MARK: - @Repeatable allows multiple occurrences

    @Test func testRepeatableAnnotationAllowsMultipleApplications() {
        let source = """
        @Repeatable
        annotation class Tag(val value: String)

        @Tag("first")
        @Tag("second")
        class MultiTagged
        """

        let ctx = runSemaCollectingDiagnostics(source)
        // The test verifies no error-level diagnostics for using an annotation twice
        // when the annotation class is @Repeatable (stricter than substring heuristics).
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected no sema errors for @Repeatable duplicate applications, got: \(errors.map(\.message))"
        )
    }

    // MARK: - @MustBeDocumented visibility in reflection

    @Test func testMustBeDocumentedAppliedToAnnotationClassIsAccepted() {
        let source = """
        @MustBeDocumented
        annotation class PublicApi
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let targetDiags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(targetDiags.isEmpty, "Expected @MustBeDocumented to be accepted on annotation class, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testMustBeDocumentedOnAnnotationClassIsRecordedInSymbol() throws {
        let source = """
        @MustBeDocumented
        annotation class DocRequiredMark
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbolID = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("DocRequiredMark")]))
        let annotations = sema.symbols.annotations(for: symbolID)

        let v6 = annotations.contains(where: { $0.annotationFQName.hasSuffix("MustBeDocumented") })
        #expect(
            v6,
            "Expected @MustBeDocumented to be recorded on annotation symbol, got: \(annotations)"
        )
    }

    // MARK: - Getter / Setter use-site targets

    @Test func testGetterUseSiteTargetAcceptedForPropertyGetterAnnotation() {
        let source = """
        @Target(AnnotationTarget.PROPERTY_GETTER)
        annotation class GetterMark

        class Foo {
            @get:GetterMark
            val value: Int = 1
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no diagnostics for @get: use-site target on PROPERTY_GETTER annotation, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSetterUseSiteTargetAcceptedForPropertySetterAnnotation() {
        let source = """
        @Target(AnnotationTarget.PROPERTY_SETTER)
        annotation class SetterMark

        class Foo {
            @set:SetterMark
            var value: Int = 1
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no diagnostics for @set: use-site target on PROPERTY_SETTER annotation, got: \(ctx.diagnostics.diagnostics)")
    }

    // MARK: - Object and enum class targets

    @Test func testTargetClassAcceptsObjectDeclaration() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassMark

        @ClassMark
        object Singleton
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no diagnostics for @ClassMark on object, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testTargetClassAcceptsEnumClass() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassMark

        @ClassMark
        enum class Color { RED, GREEN, BLUE }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no diagnostics for @ClassMark on enum class, got: \(ctx.diagnostics.diagnostics)")
    }

    // MARK: - Annotation parameters: default values, named vs positional

    @Test func testAnnotationWithDefaultParamCanBeAppliedWithNoArgs() {
        let source = """
        annotation class Label(val name: String = "default")

        @Label
        class Foo

        @Label("custom")
        class Bar
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected no diagnostics for annotation with default parameter, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testAnnotationNamedArgIsAccepted() {
        let source = """
        annotation class Configured(val level: Int = 1, val tag: String = "")

        @Configured(level = 3, tag = "release")
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected no diagnostics for annotation with named args, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testAnnotationClassIsRegisteredAsAnnotationKind() throws {
        let source = """
        annotation class MultiParam(val a: Int, val b: String)
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let symbolID = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("MultiParam")]))
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.kind == .annotationClass, "Expected MultiParam to be registered as annotationClass kind")
    }

    // MARK: - @Target(ANNOTATION_CLASS) enforcement

    @Test func testTargetAnnotationClassOnlyRejectsRegularClass() {
        let source = """
        @Target(AnnotationTarget.ANNOTATION_CLASS)
        annotation class MetaOnly

        @MetaOnly
        class NotAnAnnotation
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.count == 1, "Expected one annotation-target diagnostic for regular class, got: \(ctx.diagnostics.diagnostics)")
        let v7 = diags.allSatisfy(isError)
        #expect(v7, "Annotation-target diagnostics should be errors")
    }

    @Test func testTargetAnnotationClassOnlyAcceptsAnnotationClass() {
        let source = """
        @Target(AnnotationTarget.ANNOTATION_CLASS)
        annotation class MetaOnly

        @MetaOnly
        annotation class ValidTarget
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diags = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(diags.isEmpty, "Expected no annotation-target diagnostics for annotation class, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
