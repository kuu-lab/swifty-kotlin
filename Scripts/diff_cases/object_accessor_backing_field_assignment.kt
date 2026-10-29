// Explicit object receivers and bare assignments must share accessor backing fields.
var receiverCalls = 0

object Values {
    var annotatedGetter: Int = 1
        @JvmStatic get
    var annotatedSetter: Int = 1
        @JvmStatic set
    @JvmStatic var annotatedProperty: Int = 1
    var plain: Int = 1
    var setterCalls = 0
    var custom: Int = 1
        set(value) {
            setterCalls += 1
            field = value + 1
        }
    var nullable: Int? = null
        @JvmStatic get
    var computed: Int = 1
        get() = field + 1

    fun writeGetter(value: Int) { annotatedGetter = value }
}

fun receiver(): Values {
    receiverCalls += 1
    return Values
}

fun main() {
    receiver().annotatedGetter = 2
    println("getter=${receiver().annotatedGetter}:$receiverCalls")
    receiver().annotatedSetter = 2
    println("setter=${receiver().annotatedSetter}:$receiverCalls")
    receiver().annotatedProperty = 2
    println("property=${receiver().annotatedProperty}:$receiverCalls")
    receiver().plain = 2
    println("plain=${receiver().plain}:$receiverCalls")
    receiver().custom = 2
    println("custom=${receiver().custom}:${Values.setterCalls}:$receiverCalls")
    receiver().nullable = 2
    println("nullable=${receiver().nullable}:$receiverCalls")
    receiver().nullable = null
    println("nullableNull=${receiver().nullable == null}:$receiverCalls")
    Values.writeGetter(3)
    println("bare=${Values.annotatedGetter}:$receiverCalls")
    receiver().annotatedGetter += 2
    println("compoundGetter=${receiver().annotatedGetter}:$receiverCalls")
    receiver().annotatedSetter += 2
    println("compoundSetter=${receiver().annotatedSetter}:$receiverCalls")
    receiver().plain += 2
    println("compoundPlain=${receiver().plain}:$receiverCalls")
    receiver().custom += 2
    println("compoundCustom=${receiver().custom}:${Values.setterCalls}:$receiverCalls")
    receiver().computed = 2
    println("computed=${receiver().computed}:$receiverCalls")
    receiver().computed += 2
    println("compoundComputed=${receiver().computed}:$receiverCalls")
}
