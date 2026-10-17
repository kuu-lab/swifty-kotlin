import kotlinx.io.files.Path
import kotlinx.io.files.SystemTemporaryDirectory

fun systemTemporaryDirectoryProbe() {
    val typedValue: Path = SystemTemporaryDirectory
    val erasedValue: Any = SystemTemporaryDirectory
    val repeatedValue: Path = SystemTemporaryDirectory

    check(erasedValue is Path) { "SystemTemporaryDirectory must be a Path after erasure" }
    check(typedValue == repeatedValue) { "repeated reads must preserve the path value" }
    check(typedValue.toString().isNotEmpty()) { "SystemTemporaryDirectory must not be empty" }

    println("KOTLIN_PROPERTY_TYPE:Path")
    println("ERASED_IS_PATH:${erasedValue is Path}")
    println("KOTLIN_PATH_VALUE:${typedValue}")
    println("KOTLIN_VALUES_EQUAL:${typedValue == repeatedValue}")
    println("KOTLIN_SAME_INSTANCE:${typedValue === repeatedValue}")
}

fun main() {
    systemTemporaryDirectoryProbe()
}
