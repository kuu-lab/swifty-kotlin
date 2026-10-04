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
}
