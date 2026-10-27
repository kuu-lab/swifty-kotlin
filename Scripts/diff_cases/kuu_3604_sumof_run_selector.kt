// KUU-3604: sumOf on a direct listOf(...) receiver must infer the selector
// lambda's return type through a nested run { } block (regression coverage;
// the inference fix landed with KUU-3395, which used a val receiver).
fun main() {
    println(listOf(1, 2).sumOf { x -> run { x } })
}
