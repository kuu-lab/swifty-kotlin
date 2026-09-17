import Testing

// KUU-556: making HashMap open gives it a direct subtype for the first time.
// Map-family values still use RuntimeMapBox storage, so inherited keys/values/
// entries/size reads must stay on the runtime bridge instead of a nominal vtable.
extension BundledStdlibExecutionTests {
    @Test
    func testHashMapPropertiesDoNotUseNominalVtable() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val map: HashMap<Int, String> = hashMapOf(1 to "a")
                println(map.size)
                println(map.keys.joinToString(","))
                println(map.values.joinToString(","))
                println(map.entries.size)
            }
            """,
            expectedOutput: "1\n1\na\n1\n",
            moduleName: "KUU556HashMapPropertiesRuntime"
        )
    }

    @Test
    func testLinkedHashMapPropertiesPreserveInsertionOrder() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val map: LinkedHashMap<Int, String> = linkedMapOf(3 to "c", 1 to "a", 2 to "b")
                println(map.size)
                println(map.keys.joinToString(","))
                println(map.values.joinToString(","))
                println(map.entries.size)
            }
            """,
            expectedOutput: "3\n3,1,2\nc,a,b\n3\n",
            moduleName: "KUU556LinkedHashMapPropertiesRuntime"
        )
    }
}
