#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension AnnotationSemanticTests {

    @Test
    func testRunSemaCleanTargetRetentionRepeatableParams() throws {

        let sources: [String] = [
            """
            package sample0

                    @Target(AnnotationTarget.FUNCTION)
                    annotation class FunctionOnly

                    @FunctionOnly
                    val bad: Int = 1

            """,
            """
            package sample1

                    @Target(AnnotationTarget.PROPERTY)
                    annotation class PropOnly

                    @PropOnly
                    val fine: Int = 1

            """,
            """
            package sample2

                    @Target(AnnotationTarget.PROPERTY)
                    annotation class PropOnly

                    @PropOnly
                    class Bad

            """,
            """
            package sample3

                    annotation class Anywhere

                    @Anywhere
                    class OnClass

                    @Anywhere
                    fun onFunction() {}

                    @Anywhere
                    val onProperty: Int = 1

            """,
            """
            package sample4

                    @Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
                    annotation class ClassOrFunction

                    @ClassOrFunction
                    class Fine

                    @ClassOrFunction
                    fun alsoFine() {}

                    @ClassOrFunction
                    val bad: Int = 0

            """,
            """
            package sample5

                    @Target(AnnotationTarget.TYPEALIAS)
                    annotation class TypeAliasOnly

                    @TypeAliasOnly
                    typealias UserName = String

            """,
            """
            package sample6

                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassOnly

                    @ClassOnly
                    typealias UserName = String

            """,
            """
            package sample7

                    @Retention(AnnotationRetention.RUNTIME)
                    annotation class RuntimeAnnotation

            """,
            """
            package sample8

                    @Retention(AnnotationRetention.SOURCE)
                    annotation class SourceOnly

            """,
            """
            package sample9

                    @Repeatable
                    annotation class Tag(val value: String)

                    @Tag("first")
                    @Tag("second")
                    class MultiTagged

            """,
            """
            package sample10

                    @MustBeDocumented
                    annotation class PublicApi

            """,
            """
            package sample11

                    @MustBeDocumented
                    annotation class DocRequiredMark

            """,
            """
            package sample12

                    @Target(AnnotationTarget.PROPERTY_GETTER)
                    annotation class GetterMark

                    class Foo {
                        @get:GetterMark
                        val value: Int = 1
                    }

            """,
            """
            package sample13

                    @Target(AnnotationTarget.PROPERTY_SETTER)
                    annotation class SetterMark

                    class Foo {
                        @set:SetterMark
                        var value: Int = 1
                    }

            """,
            """
            package sample14

                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassMark

                    @ClassMark
                    object Singleton

            """,
            """
            package sample15

                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassMark

                    @ClassMark
                    enum class Color { RED, GREEN, BLUE }

            """,
            """
            package sample16

                    annotation class Label(val name: String = "default")

                    @Label
                    class Foo

                    @Label("custom")
                    class Bar

            """,
            """
            package sample17

                    annotation class Configured(val level: Int = 1, val tag: String = "")

                    @Configured(level = 3, tag = "release")
                    fun api() {}

            """,
            """
            package sample18

                    annotation class MultiParam(val a: Int, val b: String)

            """,
            """
            package sample19

                    @Target(AnnotationTarget.ANNOTATION_CLASS)
                    annotation class MetaOnly

                    @MetaOnly
                    class NotAnAnnotation

            """,
            """
            package sample20

                    @Target(AnnotationTarget.ANNOTATION_CLASS)
                    annotation class MetaOnly

                    @MetaOnly
                    annotation class ValidTarget

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diags = diagnosticsForPath(sample0Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.count == 1, "Expected one annotation-target diagnostic for property, got: \(sample0Diagnostics)")
                let v0 = diags.allSatisfy(isError)
                #expect(v0, "Annotation-target diagnostics should be errors")

            }

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diags = diagnosticsForPath(sample1Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no annotation-target diagnostics for property, got: \(sample1Diagnostics)")

            }

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diags = diagnosticsForPath(sample2Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.count == 1, "Expected one annotation-target diagnostic for class, got: \(sample2Diagnostics)")
                let v1 = diags.allSatisfy(isError)
                #expect(v1, "Annotation-target diagnostics should be errors")

            }

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let diags = diagnosticsForPath(sample3Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no annotation-target errors for annotation without @Target, got: \(sample3Diagnostics)")

            }

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let diags = diagnosticsForPath(sample4Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.count == 1, "Expected exactly one annotation-target diagnostic, got: \(sample4Diagnostics)")
                let v2 = diags.allSatisfy(isError)
                #expect(v2, "Annotation-target diagnostics should be errors")

            }

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let diags = diagnosticsForPath(sample5Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no annotation-target diagnostics for typealias, got: \(sample5Diagnostics)")

            }

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let diags = diagnosticsForPath(sample6Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.count == 1, "Expected one annotation-target diagnostic for typealias, got: \(sample6Diagnostics)")
                let v3 = diags.allSatisfy(isError)
                #expect(v3, "Annotation-target diagnostics should be errors")
                #expect(
                    diags.first?.message.contains("type alias") == true,
                    "Expected diagnostic to mention type alias usage, got: \(diags.map(\.message))"
                )

            }

            do {



                let symbolID = try #require(sema.symbols.lookup(fqName: [interner.intern("sample7"), interner.intern("RuntimeAnnotation")]))
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

            do {



                let symbolID = try #require(sema.symbols.lookup(fqName: [interner.intern("sample8"), interner.intern("SourceOnly")]))
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

            do {

                let sample9Path = paths[9]

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let errors = sample9Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected no sema errors for @Repeatable duplicate applications, got: \(errors.map(\.message))"
                )

            }

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let targetDiags = diagnosticsForPath(sample10Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(targetDiags.isEmpty, "Expected @MustBeDocumented to be accepted on annotation class, got: \(sample10Diagnostics)")

            }

            do {



                let symbolID = try #require(sema.symbols.lookup(fqName: [interner.intern("sample11"), interner.intern("DocRequiredMark")]))
                let annotations = sema.symbols.annotations(for: symbolID)

                let v6 = annotations.contains(where: { $0.annotationFQName.hasSuffix("MustBeDocumented") })
                #expect(
                    v6,
                    "Expected @MustBeDocumented to be recorded on annotation symbol, got: \(annotations)"
                )

            }

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let diags = diagnosticsForPath(sample12Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no diagnostics for @get: use-site target on PROPERTY_GETTER annotation, got: \(sample12Diagnostics)")

            }

            do {

                let sample13Path = paths[13]

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                let diags = diagnosticsForPath(sample13Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no diagnostics for @set: use-site target on PROPERTY_SETTER annotation, got: \(sample13Diagnostics)")

            }

            do {

                let sample14Path = paths[14]

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                let diags = diagnosticsForPath(sample14Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no diagnostics for @ClassMark on object, got: \(sample14Diagnostics)")

            }

            do {

                let sample15Path = paths[15]

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

                let diags = diagnosticsForPath(sample15Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no diagnostics for @ClassMark on enum class, got: \(sample15Diagnostics)")

            }

            do {

                let sample16Path = paths[16]

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                #expect(sample16Diagnostics.isEmpty, "Expected no diagnostics for annotation with default parameter, got: \(sample16Diagnostics)")

            }

            do {

                let sample17Path = paths[17]

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                #expect(sample17Diagnostics.isEmpty, "Expected no diagnostics for annotation with named args, got: \(sample17Diagnostics)")

            }

            do {



                let symbolID = try #require(sema.symbols.lookup(fqName: [interner.intern("sample18"), interner.intern("MultiParam")]))
                let symbol = try #require(sema.symbols.symbol(symbolID))

                #expect(symbol.kind == .annotationClass, "Expected MultiParam to be registered as annotationClass kind")

            }

            do {

                let sample19Path = paths[19]

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                let diags = diagnosticsForPath(sample19Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.count == 1, "Expected one annotation-target diagnostic for regular class, got: \(sample19Diagnostics)")
                let v7 = diags.allSatisfy(isError)
                #expect(v7, "Annotation-target diagnostics should be errors")

            }

            do {

                let sample20Path = paths[20]

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                let diags = diagnosticsForPath(sample20Path, withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

                #expect(diags.isEmpty, "Expected no annotation-target diagnostics for annotation class, got: \(sample20Diagnostics)")

            }

        }
    }

}

#endif
