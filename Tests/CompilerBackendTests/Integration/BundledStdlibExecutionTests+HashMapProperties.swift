import Testing

// KUU-556: making HashMap open gives it a direct subtype for the first time.
// Map-family values still use RuntimeMapBox storage, so inherited keys/values/
// entries/size reads must stay on the runtime bridge instead of a nominal vtable.
extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testHashMapSubclassObjectLiteralIndexedAssignment(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            open class A : HashMap<String, String>()
            fun box(): String {
                (object : A() {})["OK"] = "OK"
                val a = object : A() {}
                a["OK"] = "OK"
                return a["OK"]!!
            }
            fun main() { println(box()) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU2117HashMapObjectLiteralIndexedAssignment",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testHashMapSubclassMemberCalls(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("hashmap_subclass_members.kt", file: #filePath),
            expectedOutput: "5\nchild\n1\nnull\n5\n7\n3\ntrue\ntrue\n3\ntrue\ntrue\n7\nnull\n3\ntrue\n0\n1\ntrue\n1\n9\n1\n1\nnull\n1\n123\n11\n",
            moduleName: "KUU1941HashMapSubclassMembers",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

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
