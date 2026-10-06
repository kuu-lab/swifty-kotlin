import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testLocalDataClassMethods(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun makeCaptured(seed: Int): Any {
                data class Captured(val i: Int) {
                    val extra = seed
                    fun captured(): Int = seed
                }
                val value = Captured(3)
                println(value.captured())
                println(value.copy().captured())
                return value
            }
            
            fun main() {
                data class Local(val i: Int)
                println(Local(1) == Local(1))
                println(Local(1).toString())
                println(Local(1) == Local(2))
                println(Local(1).equals(null))
                println(Local(1).equals("other"))
                println(Local(1).hashCode())
                val erased: Any = Local(1)
                println(erased == Local(1))
                println(erased.toString())
                println(erased.hashCode())
                println(Local(1).copy())
                println(Local(1).copy(i = 2))
                val (i) = Local(4)
                println(i)
                val first = makeCaptured(10)
                val second = makeCaptured(20)
                println(first == second)
                println(first)
                println(first.hashCode())
                data class Custom(val i: Int) {
                    override fun equals(other: Any?): Boolean = false
                    override fun hashCode(): Int = 77
                    override fun toString(): String = "custom"
                }
                println(Custom(1) == Custom(1))
                val custom: Any = Custom(1)
                println(custom.hashCode())
                println(custom.toString())
            }
            """,
            expectedOutput: """
            true
            Local(i=1)
            false
            false
            false
            1
            true
            Local(i=1)
            1
            Local(i=1)
            Local(i=2)
            4
            10
            10
            20
            20
            true
            Captured(i=3)
            3
            false
            77
            custom
            """ + "\n",
            moduleName: "KUU1333LocalDataClass",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
