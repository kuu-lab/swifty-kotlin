// Regression for KUU-4055: `inner class` inside an enum entry's anonymous
// class body was rejected ("'Class' is prohibited here") by the enum-entry
// member collection even though kotlinc accepts it (the entry's anonymous
// class is a legal inner owner — `validateInnerPosition` allows `.enumEntry`
// sites). The rejection cascaded into unresolved `Inner`/`Child` constructor
// calls. Covers direct entry-property capture, qualified `this@X`, and a
// no-capture minimal inner class.

enum class A {
    X {
        val x = "OK"
        inner class Inner {
            val y = x
        }
        val z = Inner()
        override val test: String
            get() = z.y
    };
    abstract val test: String
}
fun boxA() = A.X.test

enum class B {
    X {
        val x = "OK"
        inner class Inner {
            fun foo() = this@X.x
        }
        val z = Inner()
        override val test = z.foo()
    };
    abstract val test: String
}
fun boxB() = B.X.test

enum class Mode {
    A {
        inner class Child
        val child = Child()
    }
}

class RegularOwner {
    inner class Child {
        val tag = "inner-ok"
    }
}
fun ordinaryInnerControl() = RegularOwner().Child().tag

enum class EntryControl {
    A {
        val result = "OK"
        fun read() = result
        override val value = read()
    };
    abstract val value: String
}

fun main() {
    println(boxA())
    println(boxB())
    println(Mode.A.name)
    println(ordinaryInnerControl())
    println(EntryControl.A.value)
}
