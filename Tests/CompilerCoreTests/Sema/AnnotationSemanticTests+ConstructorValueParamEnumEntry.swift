#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-ANNO-002: constructor / value-parameter / enum-entry annotation sema coverage
// Tests that @Target constraints are enforced on the four new usage sites:
//   primary constructor, secondary constructor, value parameter, enum entry.

extension AnnotationSemanticTests {

    @Test(arguments: ["val", "var"])
    func testUntargetedAnnotationsAcceptConstructorPropertyParameters(propertyKind: String) throws {
        let source = """
        @Target(AnnotationTarget.PROPERTY)
        annotation class PropertyOnly
        @Target(AnnotationTarget.FIELD)
        annotation class FieldOnly
        @Target(AnnotationTarget.VALUE_PARAMETER)
        annotation class ParamOnly
        @Target(AnnotationTarget.VALUE_PARAMETER, AnnotationTarget.PROPERTY, AnnotationTarget.FIELD)
        annotation class ParamPropertyField

        sealed class PartData(
            @Deprecated("Use release instead", level = DeprecationLevel.WARNING)
            public \(propertyKind) dispose: () -> Unit,
        )
        class PropertyExample(@PropertyOnly \(propertyKind) x: Int)
        class FieldExample(@FieldOnly \(propertyKind) x: Int)
        class ParamExample(@ParamOnly \(propertyKind) x: Int)
        class MultiTargetExample(@ParamPropertyField \(propertyKind) x: Int)
        class ExplicitPropertyExample(@property:PropertyOnly \(propertyKind) x: Int)
        class ExplicitFieldExample(@field:FieldOnly \(propertyKind) x: Int)
        class ExplicitParamExample(@param:ParamOnly \(propertyKind) x: Int)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter(isError)
            #expect(errors.isEmpty, "Constructor \(propertyKind) annotations should be accepted: \(errors)")
        }
    }

    @Test func testConstructorPropertyParameterAnnotationsPreserveTargetRestrictions() throws {
        let sources = [
            "@PropertyOnly x: Int",
            "@FieldOnly x: Int",
            "@Deprecated(\"old\") x: Int",
            "@GetterOnly val x: Int",
            "@SetterOnly var x: Int",
            "@FunctionOnly val x: Int",
            "@param:Deprecated(\"old\") val x: Int",
            "@param:PropertyOnly var x: Int",
            "@property:ParamOnly val x: Int",
            "@field:PropertyOnly var x: Int",
        ].enumerated().map { index, parameter in
            """
            package sample\(index)
            @Target(AnnotationTarget.PROPERTY)
            annotation class PropertyOnly
            @Target(AnnotationTarget.FIELD)
            annotation class FieldOnly
            @Target(AnnotationTarget.VALUE_PARAMETER)
            annotation class ParamOnly
            @Target(AnnotationTarget.PROPERTY_GETTER)
            annotation class GetterOnly
            @Target(AnnotationTarget.PROPERTY_SETTER)
            annotation class SetterOnly
            @Target(AnnotationTarget.FUNCTION)
            annotation class FunctionOnly

            class Example(\(parameter))
            """
        }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                let targetErrors = diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(targetErrors.count == 1, "Expected one annotation-target error: \(diagnostics)")
                #expect(targetErrors.allSatisfy(isError))
            }
        }
    }

    @Test func testConstructorValueParamEnumEntrySema() throws {
        let sources: [String] = [
            // testConstructorOnlyAnnotationAcceptedOnPrimaryConstructor
            """
            package sample0
                    @Target(AnnotationTarget.CONSTRUCTOR)
                    annotation class CtorOnly

                    class Foo @CtorOnly constructor()

            """,

            // testClassOnlyAnnotationRejectedOnPrimaryConstructor
            """
            package sample1
                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassOnly

                    class Bad @ClassOnly constructor()

            """,

            // testConstructorOnlyAnnotationAcceptedOnSecondaryConstructor
            """
            package sample2
                    @Target(AnnotationTarget.CONSTRUCTOR)
                    annotation class CtorOnly

                    class Foo(val x: Int) {
                        @CtorOnly
                        constructor() : this(0)
                    }

            """,

            // testFunctionOnlyAnnotationRejectedOnSecondaryConstructor
            """
            package sample3
                    @Target(AnnotationTarget.FUNCTION)
                    annotation class FunOnly

                    class Foo(val x: Int) {
                        @FunOnly
                        constructor() : this(0)
                    }

            """,

            // testValueParameterOnlyAnnotationAcceptedOnFunctionParam
            """
            package sample4
                    @Target(AnnotationTarget.VALUE_PARAMETER)
                    annotation class ParamOnly

                    fun greet(@ParamOnly name: String) {}

            """,

            // testClassOnlyAnnotationRejectedOnFunctionParam
            """
            package sample5
                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassOnly

                    fun greet(@ClassOnly name: String) {}

            """,

            // testValueParameterOnlyAnnotationAcceptedOnPrimaryCtorParam
            """
            package sample6
                    @Target(AnnotationTarget.VALUE_PARAMETER)
                    annotation class ParamOnly

                    class Foo(@ParamOnly val x: Int)

            """,

            // testFieldAnnotationAcceptedOnEnumEntry
            """
            package sample7
                    @Target(AnnotationTarget.FIELD)
                    annotation class FieldMark

                    enum class Color {
                        @FieldMark RED,
                        GREEN
                    }

            """,

            // testFunctionOnlyAnnotationRejectedOnEnumEntry
            """
            package sample8
                    @Target(AnnotationTarget.FUNCTION)
                    annotation class FunOnly

                    enum class Color {
                        @FunOnly RED,
                        GREEN
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testConstructorOnlyAnnotationAcceptedOnPrimaryConstructor
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.isEmpty,
                    "Expected @Target(CONSTRUCTOR) annotation to be accepted on primary constructor, got: \(sampleDiags)")
            }
            // testClassOnlyAnnotationRejectedOnPrimaryConstructor
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.count == 1,
                    "Expected @Target(CLASS) to be rejected on primary constructor, got: \(sampleDiags)")
                #expect(diags.allSatisfy(isError))
            }
            // testConstructorOnlyAnnotationAcceptedOnSecondaryConstructor
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.isEmpty,
                    "Expected @Target(CONSTRUCTOR) annotation to be accepted on secondary constructor, got: \(sampleDiags)")
            }
            // testFunctionOnlyAnnotationRejectedOnSecondaryConstructor
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.count == 1,
                    "Expected @Target(FUNCTION) to be rejected on secondary constructor, got: \(sampleDiags)")
                #expect(diags.allSatisfy(isError))
            }
            // testValueParameterOnlyAnnotationAcceptedOnFunctionParam
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.isEmpty,
                    "Expected @Target(VALUE_PARAMETER) to be accepted on function parameter, got: \(sampleDiags)")
            }
            // testClassOnlyAnnotationRejectedOnFunctionParam
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.count == 1,
                    "Expected @Target(CLASS) to be rejected on function parameter, got: \(sampleDiags)")
                #expect(diags.allSatisfy(isError))
            }
            // testValueParameterOnlyAnnotationAcceptedOnPrimaryCtorParam
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.isEmpty,
                    "Expected @Target(VALUE_PARAMETER) to be accepted on primary ctor parameter, got: \(sampleDiags)")
            }
            // testFieldAnnotationAcceptedOnEnumEntry
            do {
                let samplePath = paths[7]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.isEmpty,
                    "Expected @Target(FIELD) to be accepted on enum entry, got: \(sampleDiags)")
            }
            // testFunctionOnlyAnnotationRejectedOnEnumEntry
            do {
                let samplePath = paths[8]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diags = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(diags.count == 1,
                    "Expected @Target(FUNCTION) to be rejected on enum entry, got: \(sampleDiags)")
                #expect(diags.allSatisfy(isError))
            }

        }
    }



    // MARK: - Primary constructor annotations




    // MARK: - Secondary constructor annotations




    // MARK: - Value parameter annotations




    // MARK: - Enum entry annotations


}
#endif
