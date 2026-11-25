#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nullableCollectionAndMapIsNullOrEmptyGuardsMatchKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(
                """
                fun main() {
                    val populatedMap: Map<String, Int>? = mapOf("a" to 1)
                    println(populatedMap.isNullOrEmpty())
                    if (populatedMap.isNullOrEmpty()) {
                        println("map-empty")
                    } else {
                        println(populatedMap.containsKey("a"))
                        println(populatedMap["a"])
                    }
                    val emptyMap: Map<String, Int>? = emptyMap()
                    println(emptyMap.isNullOrEmpty())
                    val absentMap: Map<String, Int>? = null
                    println(absentMap.isNullOrEmpty())
                    if (!absentMap.isNullOrEmpty()) println(absentMap.size) else println("absent-null")
                    val populatedList: List<Int>? = listOf(1, 2)
                    println(populatedList.isNullOrEmpty())
                    if (populatedList.isNullOrEmpty()) {
                        println("list-empty")
                    } else {
                        println(populatedList.contains(2))
                    }
                    val absentList: List<Int>? = null
                    println(absentList.isNullOrEmpty())
                }
                """,
                expected: "false\ntrue\n1\ntrue\ntrue\nabsent-null\nfalse\ntrue\ntrue\n",
                mode: mode,
                root: root
            )
        }
    }
}
#endif
