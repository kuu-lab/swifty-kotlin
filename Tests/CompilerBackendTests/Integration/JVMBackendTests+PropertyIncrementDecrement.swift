#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func propertyIncrementDecrementUsesCachedReadsAndSetterResults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            var reads = 0
            var writes = 0
            var stored = 10
            var value: Int
                get() { reads++; return stored }
                set(v) { writes++; stored = v }
            var normalizedReads = 0
            var normalized: Int = 10
                get() { normalizedReads++; return field }
                set(v) { field = v * 2 }
            class Holder {
                var reads = 0
                var writes = 0
                var stored = 0
                var value: Int
                    get() { reads++; return stored }
                    set(v) { writes++; stored = v }
            }
            var receiverCalls = 0
            val holder = Holder()
            fun makeHolder(): Holder { receiverCalls++; return holder }
            fun main() {
                println(value++); println("$reads,$writes,$stored")
                println(++value); println("$reads,$writes,$stored")
                println(value--); println("$reads,$writes,$stored")
                println(--value); println("$reads,$writes,$stored")
                println(++normalized); println(normalizedReads)
                println(normalized++); println(normalizedReads)
                println(makeHolder().value++)
                println("$receiverCalls,${holder.reads},${holder.writes},${holder.stored}")
                println(++makeHolder().value)
                println("$receiverCalls,${holder.reads},${holder.writes},${holder.stored}")
                value = value + 1
                println("$reads,$writes,$stored")
            }
            """, expected: "10\n1,1,11\n12\n3,2,12\n12\n4,3,11\n10\n6,4,10\n22\n2\n22\n3\n0\n1,1,1,1\n2\n2,3,2,2\n7,5,11\n", mode: mode, root: root)
        }
    }
}
#endif
