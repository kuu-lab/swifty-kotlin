#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaAtomicReferenceMembersExecuteOnJVM(mode: EmitMode) throws {
        try assertJVM("""
        import java.util.concurrent.atomic.AtomicReference

        class SourceConfig(val value: String)

        class Holder(val sourceConfig: AtomicReference<SourceConfig>) {
            fun currentValue(): String? = sourceConfig.get()?.value
        }

        fun main() {
            val holder = Holder(AtomicReference<SourceConfig>(SourceConfig("a")))
            println(holder.currentValue())
            holder.sourceConfig.set(SourceConfig("c"))
            println(holder.currentValue())
            val previous = holder.sourceConfig.getAndSet(SourceConfig("e"))
            println(previous?.value)
            println(holder.currentValue())
        }
        """, "a\nc\nc\ne\n", mode: mode)
    }
}
#endif
