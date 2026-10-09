enum KotlinSourceFixtures {
    static let callableReferenceSamConversion = """
    fun interface IntOp { fun apply(a: Int, b: Int): Int }

    fun useOp(o: IntOp): Int = o.apply(10, 4)

    fun myCompare(a: Int, b: Int): Int = a - b

    fun main() {
        println(useOp(::myCompare))
    }
    """

    static let genericClassPropertyInitializerTypeArgument = """
    fun <X> makeIt(x: X): X = x
    class P<T : Any> {
        private val instance = makeIt<T?.() -> Int>({ 1 })
        fun read(value: T?): Int = instance(value)
    }
    """

    static let atomicfuAtomicRefStub = """
    package kotlinx.atomicfu

    class AtomicRef<T>(var value: T) {
        fun compareAndSet(expect: T, update: T): Boolean = true
    }

    fun <T> atomic(value: T): AtomicRef<T> = AtomicRef(value)
    """

    static let classOverrideInheritedDefaultArgument = """
    open class A { open fun f(x: Int = 1) = "A$x" }
    class B : A() { override fun f(x: Int) = "B$x" }
    fun probe(): String {
        val a: A = B()
        return a.f() + B().f()
    }
    """

    static let interfaceOverrideInheritedDefaultArgument = """
    interface I { fun m(x: Int = 5): String }
    class IC : I { override fun m(x: Int) = "IC$x" }
    fun probe(): String {
        val i: I = IC()
        return i.m() + IC().m()
    }
    """

    static func localNamedNominalTypingSource(declaration: String) -> String {
        """
        class Args(val x: String?)
        fun probe() {
            var args = Args("hello")
            \(declaration)
            println(args.x)
        }
        """
    }

    static let implicitReceiverSyntheticMemberProperty = """
    fun main() {
        val l = listOf(1, 2, 3)
        println(l.run { lastIndex })
        with(l) { println(indices) }
    }
    """

    static let valueKeywordExpressionBody = """
    class Holder(var value: Int)

    fun Holder.read(): Int = value

    fun Holder.other(): Int = 0
    """

    // Keep the newline after '=' because the parser tests exercise that boundary.
    static let valueKeywordExpressionBodyAfterAssignmentNewline = """
    class Holder(var value: Int)
    fun Holder.read(): Int =
        value
    fun Holder.other(): Int = 0
    """

    static let boundCallableReferenceReceiverTypeIdentity = """
    class Box {
        fun plus(x: Int): Int = x
    }
    fun main(box: Box): Int {
        val f = box::plus
        return f(7)
    }
    """

    static let nestedEscapingFunctionTypeBooleanComparison = """
    fun main() {
        val f: (Int) -> (String) -> Boolean = { m -> { s -> s.length * m > 10 } }
        println(f(2)("hello"))
        println(f(2)("hi"))
    }
    """

    static let listSortExtremaCoverage = """
    import kotlin.random.Random

    fun main() {
        val nums = listOf(3, 1, 4, 1, 5)
        println(nums.sorted())
        println(nums.sortedDescending())
        println(nums.sortedBy { it })
        println(nums.sortedByDescending { it })
        println(nums.sortedWith { a, b -> a - b })
        println(nums.shuffled())
        println(nums.shuffled(Random))
        println(nums.max())
        println(nums.min())
        println(nums.maxOrNull())
        println(nums.minOrNull())
        println(nums.maxBy { it })
        println(nums.minBy { it })
        println(nums.maxByOrNull { it })
        println(nums.minByOrNull { it })
        println(nums.maxOf { it })
        println(nums.minOf { it })
        println(nums.maxOfOrNull { it })
        println(nums.minOfOrNull { it })
        println(nums.maxWith { a, b -> a - b })
        println(nums.minWith { a, b -> a - b })
        println(nums.maxWithOrNull(naturalOrder()))
        println(nums.minWithOrNull(naturalOrder()))
        println(nums.maxOfWith(naturalOrder()) { it })
        println(nums.minOfWith(naturalOrder()) { it })
        println(nums.maxOfWithOrNull(naturalOrder()) { it })
        println(nums.minOfWithOrNull(naturalOrder()) { it })
    }
    """
}
