fun main() {
    println(generateSequence('A') { null }.toList())
    println(generateSequence('A') { if (it == 'A') 'B' else null }.toList())
    println(generateSequence(1.5) { if (it == 1.5) 2.5 else null }.toList())
    println(generateSequence(1) { if (it < 3) it + 1 else null }.toList())
    println(generateSequence { null }.toList())
    println(sequence { yield('X'); yield('Y') }.toList())
    println(sequence { yield(1.5); yield(2.5) }.toList())
}
