// KUU-3619: value class secondary constructors delegate to the primary
// constructor and must be accepted on the native backend (JetBrains
// testData: simpleSecondaryConstructor, secondaryConstructorsInsideInlineClass,
// secondaryConstructorsWithBody, secondaryConstructorWithVararg,
// secondaryConstructorVisibilies, kt46554).

@JvmInline
value class Foo(val x: String) {
    // Delegation, early return and a Unit return inside a secondary body.
    constructor(y: Int) : this("OK") {
        if (y == 0) throw IllegalArgumentException()
        if (y == 1) return
        return Unit
    }

    // Secondary -> secondary delegation chain.
    constructor(z: Double) : this(z.toInt())
}

@JvmInline
value class Multi(val x: String) {
    constructor(y: Int) : this(y.toString())
    constructor(z: Long) : this(z.toInt() + 1)
    constructor(a: Int, b: Int) : this((a + b).toString())
}

@JvmInline
value class VarargCtor(val x: Int) {
    constructor(vararg ys: Long) : this(ys.size)
}

@JvmInline
value class Vis(val x: Int) {
    public constructor() : this(0)
    internal constructor(x: Long, y: Int) : this(x.toInt(), y)
    private constructor(x: Int, y: Int) : this(x + y)
}

var initResult = "Fail"

@JvmInline
value class WithInit(val value: String) {
    constructor() : this("OK")

    init {
        initResult = value
    }
}

var bodyLog = mutableListOf<Int>()

@JvmInline
value class WithBody(val x: Int) {
    constructor(xD: Double) : this(-xD.toInt()) {
        bodyLog.add(x)
        bodyLog.add(this.x)
    }
}

@JvmInline
value class Boxed(val array: IntArray) {
    constructor(size: Int) : this(IntArray(size))
    operator fun get(index: Int): Int = array[index]
    operator fun set(index: Int, value: Int) {
        array[index] = value
    }
}

fun main() {
    println(Foo(42.0).x)

    println(Multi(42).x)
    println(Multi(43L).x)
    println(Multi(1, 2).x)

    println(VarargCtor(111).x)
    println(VarargCtor().x)
    println(VarargCtor(2222L).x)

    println(Vis(111).x)
    println(Vis().x)
    println(Vis(2222L, 100).x)

    WithInit()
    println(initResult)

    val wb = WithBody(-1.5)
    println(wb.x)
    println(bodyLog)

    val boxed = Boxed(4)
    boxed[0] = 7
    println(boxed[0])
}
