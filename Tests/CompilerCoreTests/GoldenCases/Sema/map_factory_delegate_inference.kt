package golden.sema

// KUU-4578: a zero-argument mapOf() delegate must infer K = String and
// V = property type through the Map.getValue convention bounds.
fun mapFactoryDelegateInference() {
    val count: Int by mapOf()
    val name: String by mapOf()
}
