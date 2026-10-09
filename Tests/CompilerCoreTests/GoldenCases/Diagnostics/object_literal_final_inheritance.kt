package golden.diagnostics

class A
fun directAnonymous() = object : A() {}

class FinalBase<T>
typealias FinalAlias<T> = FinalBase<T>

class NamedFinal : FinalAlias<String>()
fun anonymousFinal() = object : FinalAlias<String>() {}

data class DataBase(val value: Int)
class NamedData : DataBase(1)
fun anonymousData() = object : DataBase(2) {}

open class OpenBase<T>
abstract class AbstractBase {
    fun implemented(): Int = 1
}
interface Contract

fun allowed() {
    val open = object : OpenBase<String>() {}
    val abstract = object : AbstractBase() {}
    val contract = object : Contract {}
    val any = object : Any() {}
}

fun bundledFinal() =
    object : kotlin.DeepRecursiveFunction<Int, Int>({ n -> n * 2 }) {}
