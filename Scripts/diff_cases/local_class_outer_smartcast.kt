// A local class member must keep the enclosing function's non-null smart cast
// on a captured outer stable property (KUU-4605). kotlinc accepts all of these.
class Outer {
    val stable: String? = "ok"

    fun explicitReturn() {
        if (stable != null) {
            class Local {
                fun read(): String = stable
            }
            val s: String = Local().read()
            println(s)
        }
    }

    fun inferredReturn() {
        if (stable != null) {
            class Local {
                fun read() = stable
            }
            // The inferred return type must be String, not String?, so this
            // assignment only type-checks when the smart cast survives.
            val s: String = Local().read()
            println(s)
        }
    }

    fun blockBody() {
        if (stable != null) {
            class Local {
                fun read(): String {
                    return stable
                }
            }
            val s: String = Local().read()
            println(s)
        }
    }

    fun localValCapture() {
        val captured: String? = "local"
        if (captured != null) {
            class Local {
                fun read() = captured
            }
            val s: String = Local().read()
            println(s)
        }
    }
}

fun main() {
    val outer = Outer()
    outer.explicitReturn()
    outer.inferredReturn()
    outer.blockBody()
    outer.localValCapture()
}
