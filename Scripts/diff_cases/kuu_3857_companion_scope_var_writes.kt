// KOTLINC_FLAGS: -Xcompanion-blocks-and-extensions
// KUU-3857: writes through a class-name qualifier must resolve against the
// companion scope exactly like reads do — `companion var T.x` extensions
// (with and without a source `companion object`), `companion { }` block
// members, and `companion object` members all accept `=`/`+=`/`++`/`--`.
// Block-member writes must additionally trigger the hidden object's lazy
// initializer before storing, or the object's own initializers clobber the
// value at a later read.
class A
companion var A.compExtVar: Int = 1

class B { companion object {} }
companion var B.compExtVarObj: Int = 10

class C { companion { var blockVar = 0 } }

class D { companion object { var objVar = 20 } }

class E { companion { var customVar = 3; set(value) { field = value * 2 } } }

fun main() {
    // Initializer values
    println(A.compExtVar)
    println(B.compExtVarObj)
    println(C.blockVar)
    println(D.objVar)
    println(E.customVar)

    // Plain writes
    A.compExtVar = 2
    B.compExtVarObj = 30
    C.blockVar = 40
    D.objVar = 50
    E.customVar = 4
    println(A.compExtVar)
    println(B.compExtVarObj)
    println(C.blockVar)
    println(D.objVar)
    println(E.customVar)

    // Compound writes
    A.compExtVar += 1
    B.compExtVarObj += 1
    C.blockVar += 1
    D.objVar += 1
    println(A.compExtVar)
    println(B.compExtVarObj)
    println(C.blockVar)
    println(D.objVar)

    // Increment/decrement
    A.compExtVar++
    B.compExtVarObj++
    C.blockVar--
    D.objVar--
    println(A.compExtVar)
    println(B.compExtVarObj)
    println(C.blockVar)
    println(D.objVar)
}
