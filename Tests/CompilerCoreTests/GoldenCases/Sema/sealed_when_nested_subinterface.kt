sealed interface F
sealed interface N : F
class A : N
class B : N
class C : F

fun s(f: F): String {
    return when (f) {
        is A -> "a"
        is B -> "b"
        is C -> "c"
    }
}

fun partial(f: F): String {
    return when (f) {
        is A -> "a"
        is C -> "c"
    }
}
