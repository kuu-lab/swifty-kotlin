#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func primitiveBoundCompoundAndComparisonPreserveUserDispatch(mode: EmitMode) throws {
        try assertJVM("""
        fun <T : Int> shift(v: T): Char { var c = 'a'; c += v; return c }
        fun <T : Int> lower(v: T): Char { var c = 'b'; c -= v; return c }
        class Letters(var letter: Char)
        fun <T : Int> propertyShift(v: T): Char { val box = Letters('a'); box.letter += v; return box.letter }
        fun <T : Double> compound(v: T): Double { var result = 1.0; result += v; return result }
        fun <T : Float> floatCompound(v: T): Float { var result = 1.0f; result *= v; return result }
        fun <T : Long> longCompound(v: T): Long { var result = 1L; result += v; return result }
        fun <T : Int> compare(v: T): Int = v.compareTo(3.0)
        fun <T : Byte> byteCompare(v: T): Int = v.compareTo(3L)
        fun <T : Short> shortCompare(v: T): Int = v.compareTo(3.0f)
        fun <T : Int> T.compareTo(other: String): T = this
        fun <T : Int> extension(v: T): T = v.compareTo("tag")
        class Counter(var result: Int) {
            operator fun plusAssign(other: Double) { result += 7 }
        }
        fun <T : Double> custom(v: T): Int { val c = Counter(0); c += v; return c.result }
        fun main() {
            println(compound(2.0)); println(floatCompound(2.0f)); println(longCompound(2L))
            println(compare(2)); println(byteCompare(2)); println(shortCompare(2))
            println(extension(5)); println(custom(2.0))
            println(shift(1)); println(lower(1)); println(propertyShift(1))
        }
        """, "3.0\n2.0\n3\n-1\n-1\n-1\n5\n7\nb\na\nb\n", mode: mode)
    }
}
#endif
