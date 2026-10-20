import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testCustomPropertyAccessorExceptionsPropagate(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            object ObjectAccessors {
                var value: Int = 0
                    get() {
                        require(false) { "object getter" }
                        return field
                    }
                    set(value) {
                        require(false) { "object setter" }
                        field = value
                    }
            }
            class ClassAccessors {
                var value: Int = 0
                    get() {
                        require(false) { "class getter" }
                        return field
                    }
                    set(value) {
                        require(false) { "class setter" }
                        field = value
                    }
            }
            fun main() {
                try { ObjectAccessors.value = 1 }
                catch (error: IllegalArgumentException) { println(error.message) }
                try { ObjectAccessors.value }
                catch (error: IllegalArgumentException) { println(error.message) }

                val instance = ClassAccessors()
                try { instance.value = 1 }
                catch (error: IllegalArgumentException) { println(error.message) }
                try { instance.value }
                catch (error: IllegalArgumentException) { println(error.message) }
            }
            """,
            expectedOutput: "object setter\nobject getter\nclass setter\nclass getter\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
