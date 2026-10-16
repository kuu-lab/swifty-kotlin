interface Container<T>
class TextContainer : Container<String>
class NumberContainer : Container<Int>

fun <T> choose(a: T, b: T): T = a

fun incompatibleContainerBound(): Container<String> =
    choose(TextContainer(), NumberContainer())
