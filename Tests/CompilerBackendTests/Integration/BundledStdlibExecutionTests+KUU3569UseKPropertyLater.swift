@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testKUU3569UseKPropertyLater() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KProperty

            val properties = HashSet<KProperty<*>>()

            object Delegate {
                operator fun getValue(t: Any?, p: KProperty<*>): String {
                    properties.add(p)
                    return ""
                }

                operator fun setValue(t: Any?, p: KProperty<*>, value: String) {
                    properties.add(p)
                }
            }

            var topLevel: String by Delegate

            object O {
                var member: String by Delegate
                var O.memExt: String by Delegate
            }

            fun main() {
                topLevel
                O.member
                O.memExt
                topLevel = "top"
                O.member = "member"
                O.memExt = "extension"

                val names = ArrayList<String>()
                for (property in HashSet(properties)) {
                    names.add(property.name)
                }
                println(names.joinToString(","))
            }
            """,
            expectedOutput: "topLevel,member,memExt\n",
            moduleName: "KUU3569UseKPropertyLater"
        )
    }
}
