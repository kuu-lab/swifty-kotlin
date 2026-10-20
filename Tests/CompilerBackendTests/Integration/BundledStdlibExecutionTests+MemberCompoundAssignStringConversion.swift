import Testing

// End-to-end (compiled and run) counterpart of the KIR-structural checks in
// CompilerCoreTests/Lowering/LoweringPassRegressionTests+MemberCompoundAssignStringConversion.swift.
// `receiver.field += x` where `field: String` and `x` is not itself a String
// used to skip Any-to-String conversion entirely: a class instance silently
// vanished from the result and a primitive value crashed the process. See
// that file's header comment for the full root-cause writeup.
extension BundledStdlibExecutionTests {
    @Test
    func testMemberFieldCompoundAssignConvertsPrimitiveAndClassRHS() throws {
        try compileAndRunKotlin(
            """
            class Foo(val x: Int) {
                override fun toString(): String = "Foo(" + x + ")"
            }
            class Holder(var s: String)
            fun main() {
                val h = Holder("start=")
                h.s += Foo(1)
                println(h.s)

                val h2 = Holder("n=")
                h2.s += 42
                println(h2.s)

                val h3 = Holder("b=")
                h3.s += true
                println(h3.s)

                val h4 = Holder("nullable=")
                val nf: Foo? = null
                h4.s += nf
                println(h4.s)
            }
            """,
            expectedOutput: "start=Foo(1)\nn=42\nb=true\nnullable=null\n"
        )
    }

    @Test
    func testIndexedStringCompoundAssignConvertsArbitraryRHS() throws {
        try compileAndRunKotlin(
            """
            class Item { override fun toString(): String = "item" }
            class NullableHolder(var text: String?)
            fun fromBody(): String { do { return "body" } while ("${throw IllegalStateException("bad")}" == "x") }
            fun main() {
                val strings = arrayOf("a")
                strings[0] += 2; strings[0] += true; strings[0] += Item()
                println(strings[0])
                val nullable = arrayOf<String?>(null)
                nullable[0] += 3; println(nullable[0])
                val list = mutableListOf("l"); list[0] += false; println(list[0])
                val map = mutableMapOf(1 to "m"); map[1] += 4; map[2] += 5
                println(map[1]); println(map[2]); println(fromBody())
                var text: String? = null; text += 42
                val normalized: String = text; println(normalized)
                val holder = NullableHolder(null); holder.text += true; println(holder.text)
            }
            """,
            expectedOutput: "a2trueitem\nnull3\nlfalse\nm4\nnull5\nbody\nnull42\nnulltrue\n"
        )
    }

}
