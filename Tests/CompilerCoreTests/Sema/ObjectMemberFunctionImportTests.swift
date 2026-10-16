@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct ObjectMemberFunctionImportTests {
    @Test(arguments: [
        ("import views.Factories.freeze", "freeze"),
        ("import views.Factories.freeze as freeze", "freeze"),
        ("import views.Factories.freeze as frozenCopy", "frozenCopy"),
        ("import views.Factories", "Factories.freeze"),
        ("import views.Factories as Views", "Views.freeze"),
    ])
    func genericObjectMemberAcrossFiles(importAndCall: (String, String)) throws {
        try withTemporaryFiles(contents: [
            """
            package views
            object Factories {
                fun <T> freeze(values: List<T>): List<T> = values
            }
            """,
            """
            \(importAndCall.0)
            fun frozen(values: List<String>): List<String> = \(importAndCall.1)(values)
            fun main() {}
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func sameFileObjectMemberImportsResolveAlongsideOverloads() throws {
        try withTemporaryFiles(contents: [
            """
            package views

            import views.Factories.freeze
            import views.Factories.freeze as frozenCopy
            import views.Numbers.convert
            import views.Words.convert

            class Box<T>(val value: T)

            object Factories {
                fun <T> freeze(values: Box<T>): Box<T> = values
            }
            object Numbers {
                fun convert(value: Int): Int = value
                fun convert(value: Int, block: (Int) -> Int): Int = block(value)
            }
            object Words {
                fun convert(value: String): String = value
                fun convert(value: String, block: (String) -> String): String = block(value)
            }

            fun frozen(values: Box<String>): Box<String> = freeze(values)
            fun copied(values: Box<String>): Box<String> = frozenCopy(values)
            fun number(): Int = convert(3)
            fun word(): String = convert("ok")
            fun numberWithTransform(): Int = convert(3) { it + 1 }
            fun wordWithTransform(): String = convert("ok") { it + "!" }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func importedOverloadsUseEachObjectReceiver() throws {
        try withTemporaryFiles(contents: [
            """
            package views
            object Numbers { fun convert(value: Int): Int = value }
            object Words { fun convert(value: String): String = value }
            """,
            """
            import views.Numbers.convert
            import views.Words.convert
            fun number(): Int = convert(1)
            fun word(): String = convert("word")
            class Reader { fun read(): String = convert("reader") }
            fun Int.read(): String = convert("extension")
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func instanceMemberImportStillRequiresReceiver(aliased: Bool) throws {
        try withTemporaryFiles(contents: [
            "package views\nclass Factory { fun freeze(value: Int): Int = value }",
            """
            import views.Factory.freeze\(aliased ? " as frozenCopy" : "")
            fun frozen(): Int = \(aliased ? "frozenCopy" : "freeze")(1)
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "\(errors)")
        }
    }

    @Test
    func importedOverloadsContextualizeImplicitLambdaParameters() throws {
        try withTemporaryFiles(contents: [
            """
            package views
            object Numbers {
                fun convert(value: Int, block: (Int) -> Int): Int = block(value)
            }
            object Words {
                fun convert(value: String, block: (String) -> String): String = block(value)
            }
            """,
            """
            import views.Numbers.convert
            import views.Words.convert
            fun number(): Int = convert(1) { it + 1 }
            fun word(): String = convert("word") { it + "!" }
            class Reader { fun read(): Int = convert(2) { it + 2 } }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func equallyApplicableImportsRemainAmbiguous() throws {
        try withTemporaryFiles(contents: [
            """
            package views
            object First { fun freeze(value: Int): Int = value }
            object Second { fun freeze(value: Int): Int = value }
            """,
            """
            import views.First.freeze
            import views.Second.freeze
            fun frozen(): Int = freeze(1)
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" },
                    "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func objectMemberExtensionImportStillRequiresExtensionReceiver() throws {
        try withTemporaryFiles(contents: [
            "package views\nobject Factory { fun Int.freeze(): Int = this }",
            """
            import views.Factory.freeze as frozenCopy
            fun frozen(): Int = frozenCopy()
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected a missing extension receiver diagnostic")
        }
    }

    @Test(arguments: [false, true])
    func nullableExplicitObjectReceiverStillRequiresSafeCall(safe: Bool) throws {
        try withTemporaryFiles(contents: ["""
            object Factory { fun value(): Int = 1 }
            fun read(factory: Factory?): Int\(safe ? "?" : "") = factory\(safe ? "?." : ".")value()
            """]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == !safe, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func bareImportDoesNotCacheSuccessForNullableExplicitReceiver() throws {
        try withTemporaryFiles(contents: [
            "package views\nobject Factory { fun value(): Int = 1 }",
            """
            import views.Factory
            import views.Factory.value
            fun Factory?.read(): Int {
                value()
                return this.value()
            }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0002", "\(errors)")
        }
    }

    @Test
    func nullableImplicitObjectReceiverWithoutImportIsRejected() throws {
        try withTemporaryFiles(contents: ["""
            object Factory { fun value(): Int = 1 }
            fun Factory?.read(): Int = value()
            """]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func smartCastImplicitObjectReceiverWithoutImportStillWorks() throws {
        try withTemporaryFiles(contents: ["""
            object Factory { fun value(): Int = 1 }
            fun Factory?.read(): Int {
                if (this == null) return 0
                return value()
            }
            """]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
