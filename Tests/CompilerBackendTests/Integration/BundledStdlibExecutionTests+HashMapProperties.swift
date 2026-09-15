import Testing

// KUU-556: HashMap.kt became `open` so LinkedHashMap could subclass it, which
// gave HashMap its first-ever direct subtype. That made KSP-928's
// abstract/open-property vtable dispatch rule in
// CallLowerer+MemberPropertyReads.swift start matching HashMap's own
// materialized realization of the four Map interface properties it never
// overrides in source (size/keys/values/entries -- @KsSymbolName isn't wired
// for .property symbols yet), because "owner has a direct subtype" became
// true for the first time. That realization carries no external link of its
// own (only Map's original declaration does) and LayoutSynthesis assigns it a
// real vtable slot, but every Map-family value here shares one RuntimeMapBox
// representation with no true per-class vtable, so dispatching through that
// slot panicked at runtime (KSWIFTK-RUNTIME-0001) instead of reaching Map's
// external-link bridge -- for *any* HashMap- or LinkedHashMap-typed receiver,
// not just ones produced by a Map HOF.
extension BundledStdlibExecutionTests {
    @Test
    func testHashMapKeysValuesEntriesSizeDoNotPanic() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val m: HashMap<Int, String> = hashMapOf(1 to "a")
                println(m.size)
                println(m.keys.joinToString(","))
                println(m.values.joinToString(","))
                println(m.entries.size)
            }
            """,
            expectedOutput: "1\n1\na\n1\n",
            moduleName: "KUU556HashMapPropertiesRuntime"
        )
    }

    @Test
    func testLinkedHashMapKeysValuesEntriesSizePreserveInsertionOrder() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val m: LinkedHashMap<Int, String> = linkedMapOf(3 to "c", 1 to "a", 2 to "b")
                println(m.size)
                println(m.keys.joinToString(","))
                println(m.values.joinToString(","))
                println(m.entries.size)
            }
            """,
            expectedOutput: "3\n3,1,2\nc,a,b\n3\n",
            moduleName: "KUU556LinkedHashMapPropertiesRuntime"
        )
    }
}
