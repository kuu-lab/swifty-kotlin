class ReflectedBox(var content: String)

fun main() {
    val receiver = ReflectedBox("before")
    val reference = ReflectedBox::content
    check(reference.get(receiver) == "before")
    reference.set(receiver, "after")
    check(reference(receiver) == "after")
    println("ok")
}
