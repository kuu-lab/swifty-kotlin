import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testKotlinJSAnnotationSyntaxOnNativeTarget() throws {
        try compileAndRunKotlin(
            """
            @JsName("myRenamedFunction")
            fun namedFunction(): String = "renamed"

            @JsExport
            class ExportedClass {
                val value: Int = 42

                @JsName("computeDouble")
                fun compute(): Int = value * 2
            }

            // This native-target smoke checks the accepted annotation syntax.
            // JS module linking is outside this backend, so use a body-backed class.
            @JsModule("some-npm-package")
            @JsName("SomeModuleClass")
            class ModuleAnnotatedClass {
                fun doSomething(): String = "native"
            }

            fun main() {
                val exported = ExportedClass()
                println(exported.value)
                println(exported.compute())
                println(namedFunction())
                println("js_api ok")
            }
            """,
            expectedOutput: "42\n84\nrenamed\njs_api ok\n",
            moduleName: "KUU1481KotlinJSAnnotations"
        )
    }
}
