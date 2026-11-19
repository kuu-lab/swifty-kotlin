#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unitPairValuesMatchKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
                inline fun <T> T.singletonList(): List<T> = listOf(this)
                fun effect(label: String) { println(label) }

                fun main() {
                    val pair = Unit to 1
                    println(pair.second)
                    println(pair.first)
                    println(2 to Unit)
                    val effects = effect("left") to effect("right")
                    println(effects)
                    println(effects.component2())
                    println(Unit.singletonList())
                }
                """, expected: """
                1
                kotlin.Unit
                (2, kotlin.Unit)
                left
                right
                (kotlin.Unit, kotlin.Unit)
                kotlin.Unit
                [kotlin.Unit]

                """, mode: mode, root: root)
        }
    }
}
#endif
