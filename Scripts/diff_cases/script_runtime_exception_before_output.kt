// kotlinc -script and the compiled native candidate use different exit codes
// for an uncaught runtime exception. Pin both runner-specific results while
// the diff harness still requires candidate compilation and matching stdout.
// DIFF_EXPECT_SCRIPT_EXIT: ref=3 candidate=1
val x = 10 / 0
println("unreachable")
