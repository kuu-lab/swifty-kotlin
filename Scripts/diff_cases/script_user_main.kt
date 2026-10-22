// WITH_STDLIB
// KUU-2800: a script file may declare `fun main` alongside top-level
// statements. The synthesized script entry point must not collide with the
// declared one (SEMA-0001), and the script body is the program entry
// (matching `kotlinc -script`, which runs the top-level statements).
fun main() { println("user main") }

println("script stmt")
