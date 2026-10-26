@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InnerClassOuterProtectedPropertyTests {
    @Test
    func protectedOuterPropertyIsVisibleFromNestedClassesOnly() throws {
        let source = """
        interface Accessor {
            val x: Int
        }

        class Foo {
            protected val x: Int = 0

            inner class Inner : Accessor {
                override val x: Int = this@Foo.x
            }
        }

        class MinimalFoo {
            protected val x: Int = 0

            inner class Inner {
                val copied: Int = this@MinimalFoo.x
            }
        }

        class PublicFoo {
            val x: Int = 0

            inner class Inner {
                val copied: Int = this@PublicFoo.x
            }
        }

        class Unrelated {
            fun read(foo: MinimalFoo): Int = foo.x
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0041", "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.message.contains("'x'") == true, "Unexpected diagnostics: \(errors)")
        }
    }
}
