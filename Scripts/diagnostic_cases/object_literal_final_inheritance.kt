// EXPECT-REJECT
// Final user classes are rejected through a generic typealias for both named
// classes and anonymous objects.
class A
fun directAnonymous() = object : A() {}

class FinalBase<T>
typealias FinalAlias<T> = FinalBase<T>
class NamedFinal : FinalAlias<String>()
fun anonymousFinal() = object : FinalAlias<String>() {}

// Data classes have the same rule for both inheritance forms.
data class DataBase(val value: Int)
class NamedData : DataBase(1)
fun anonymousData() = object : DataBase(2) {}

// Bundled Kotlin metadata must mark this final class as non-subclassable too.
fun bundledFinal() = object : kotlin.DeepRecursiveFunction<Int, Int>({ n -> n * 2 }) {}
