// KUU-4466: kotlinc drops a generic overload whose type parameter is not
// inferable from the call (it does not occur in parameter or return types),
// so the non-generic `kc` wins instead of producing ambiguity.
typealias Decl = () -> Unit
fun kc(declaration: Decl): String = "nongeneric"
fun <T : Any> kc(appDeclaration: Decl? = null, tag: Int = 0): Int = 2
fun main() {
    println(kc { })
}
