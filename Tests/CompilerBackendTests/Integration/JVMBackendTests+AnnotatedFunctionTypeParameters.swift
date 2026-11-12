#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func annotatedFunctionTypesPreserveNamedParameters(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            @Target(AnnotationTarget.TYPE)
            annotation class Marker(val id: Int = 0)

            fun <T> apply(value: T, transform: @Marker (item: T) -> String): String =
                transform(value)

            fun add(transform: @Marker(2) (left: Int, right: Int) -> Int): Int =
                transform(2, 3)

            fun main() {
                println(apply(4) { "item=$it" })
                println(add { left, right -> left + right })
            }
            """, expected: "item=4\n5\n", mode: mode, root: root)
        }
    }
}
#endif
