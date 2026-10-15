import java.lang.reflect.Modifier

fun box(): String =
    if (Modifier.FINAL == 16 && Modifier.PUBLIC == 1 && Modifier.STATIC == 8) "OK" else "FAIL"

fun main() {
    println(box())
}
