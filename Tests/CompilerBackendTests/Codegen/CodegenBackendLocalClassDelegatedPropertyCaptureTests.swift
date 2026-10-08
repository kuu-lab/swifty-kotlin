#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendLocalClassDelegatedPropertyCaptureTests {

    @Test
    func testCapturedMapUsedOnlyAsLocalClassDelegate() throws {
        let source = """
        fun main() {
            val m = mapOf("k" to "v")
            class D { val k by m }
            class E { val x = m }
            class F { val k by m; fun direct() = m }

            println(D().k)
            println(E().x)
            println(F().k)
            println(F().direct())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalClassDelegatedMapCapture",
            expected: "v\n{k=v}\nv\n{k=v}\n"
        )
    }

    @Test
    func testCustomDelegateCaptureSurvivesCreatorReturnAndInitializesPerInstance() throws {
        let source = """
        import kotlin.reflect.KProperty

        class ValueDelegate<T>(private val stored: T) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): T = stored
        }

        fun makeReader(): () -> String {
            val label = "captured"
            var initialized = 0
            class Box {
                val value by ValueDelegate(label)
                val instance by ValueDelegate(++initialized)
                fun read(): String = "$value:$instance"
            }

            val first = Box()
            val second = Box()
            return { first.read() + "|" + second.read() }
        }

        fun main() {
            val read = makeReader()
            println(read())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalClassCustomDelegateCapture",
            expected: "captured:1|captured:2\n"
        )
    }
}
#endif
