#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func inheritedGenericDefaultsBoxPrimitiveArguments(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            interface Api<T> { fun number(input: T, suffix: String = "!"): String }
            open class IntBase { fun number(input: Int, suffix: String): String = "$input$suffix" }
            class IntLeaf: IntBase(), Api<Int> { fun implicit(): String = number(12) }
            open class LongBase { fun number(input: Long, suffix: String): String = "$input$suffix" }
            class LongLeaf: LongBase(), Api<Long>
            open class DoubleBase { fun number(input: Double, suffix: String): String = "$input$suffix" }
            class DoubleLeaf: DoubleBase(), Api<Double>
            fun main() {
                val leaf = IntLeaf()
                println(leaf.number(9))
                println(leaf.number(input = 10))
                println(leaf.number(11, "?"))
                println(leaf.implicit())
                val api: Api<Int> = leaf
                println(api.number(13))
                val present: IntLeaf? = leaf
                val absent: IntLeaf? = null
                println(present?.number(14))
                println(absent?.number(15))
                println(LongLeaf().number(21L))
                println(DoubleLeaf().number(1.5))
            }
            """, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", artifact.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "9!\n10!\n11?\n12!\n13!\n14!\nnull\n21!\n1.5!\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
