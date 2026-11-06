// EXPECT-REJECT
class D {
    operator fun getValue(t: Any?, p: Any?): Int = 1
}
val x by D()
    : Int
