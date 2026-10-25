// KUU-3182: a local function's default parameter expression that captures an
// outer local must receive that value through every enclosing callable's
// environment -- nested local functions, lambdas, and local-class members
// alike (JetBrains closures/kt5589 shape).

// Control: single-level capture directly in the declaring function.
fun direct(): String {
    val x = "OK"
    fun bar(y: String = x): String = y
    return bar()
}

// Regression: `x` is only referenced by `bar`'s default expression, one
// nesting level removed from its declaring scope.
fun nested(): String {
    val x = "OK"
    fun outer(): String {
        fun bar(y: String = x): String = y
        return bar()
    }
    return outer()
}

// Three levels deep: the capture must be threaded through `middle` too.
fun nestedTwice(): String {
    val x = "OK"
    fun outer(): String {
        fun middle(): String {
            fun bar(y: String = x): String = y
            return bar()
        }
        return middle()
    }
    return outer()
}

// A mutable capture reads the current cell value at call time.
fun mutableCapture(): String {
    var x = "OK"
    fun outer(): String {
        fun bar(y: String = x): String = y
        x = "CHANGED"
        return bar()
    }
    return outer()
}

// Mixed provided and defaulted parameters: `y` still resolves `x`.
fun mixedParams(): String {
    val x = "OK"
    fun outer(): String {
        fun bar(a: String = "A", y: String = x): String = a + y
        return bar()
    }
    return outer()
}

// A local function declared inside a lambda body.
fun inLambda(): String {
    val x = "OK"
    val f = {
        fun bar(y: String = x): String = y
        bar()
    }
    return f()
}

// A local function declared inside a named local class's member.
fun inLocalClass(): String {
    val x = "OK"
    class L {
        fun m(): String {
            fun bar(y: String = x): String = y
            return bar()
        }
    }
    return L().m()
}

// A local function declared inside an object expression's member.
fun inObjectLiteral(): String {
    val x = "OK"
    val o = object {
        fun m(): String {
            fun bar(y: String = x): String = y
            return bar()
        }
    }
    return o.m()
}

// The captured symbol is the enclosing generic function's type parameter.
fun <T> generic(t: T): String {
    fun outer(): String {
        fun bar(y: T = t): T = y
        return bar().toString()
    }
    return outer()
}

// The default expression reads an enclosing class member through `this`.
class MemberDefault {
    val s = "OK"
    fun method(): String {
        fun outer(): String {
            fun bar(y: String = this@MemberDefault.s): String = y
            return bar()
        }
        return outer()
    }
}

fun main() {
    print(direct())
    print("|" + nested())
    print("|" + nestedTwice())
    print("|" + mutableCapture())
    print("|" + mixedParams())
    print("|" + inLambda())
    print("|" + inLocalClass())
    print("|" + inObjectLiteral())
    print("|" + generic("OK"))
    print("|" + MemberDefault().method())
}
