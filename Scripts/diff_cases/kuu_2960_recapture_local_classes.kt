// KUU-2960: local functions and local classes must share mutable capture cells.
fun recaptureVarCapturedInLocalClass1(): String {
    var x = ""
    class CapturesX {
        override fun toString() = x
    }
    fun localFun() = CapturesX()
    x = "OK"
    return localFun().toString()
}

fun recaptureVarCapturedInLocalClass2(): String {
    var x = ""
    class CapturesX {
        override fun toString() = x
    }
    fun outerFun1(): CapturesX {
        fun localFun() = CapturesX()
        return localFun()
    }
    x = "OK"
    return outerFun1().toString()
}

fun recaptureVarCapturedInLocalClass3(): String {
    var x = ""
    class CapturesX {
        override fun toString() = x
    }
    class LocalClass {
        fun foo() = CapturesX()
    }
    x = "OK"
    return LocalClass().foo().toString()
}

fun main() {
    println(recaptureVarCapturedInLocalClass1())
    println(recaptureVarCapturedInLocalClass2())
    println(recaptureVarCapturedInLocalClass3())
}
