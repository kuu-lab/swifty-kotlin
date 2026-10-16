// DIFF_CANDIDATE_ONLY_FROM_SOURCE: Exercises the reported local-class type-parameter failure.
// EXPECT-STDOUT: OK
fun main() {
    class Local<T>(val value: T)
    println(Local<String>("OK").value)
}
