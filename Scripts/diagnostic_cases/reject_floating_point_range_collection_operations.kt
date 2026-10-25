// EXPECT-REJECT
fun doubleRangeToList() { (1.0..3.0).toList() }
fun floatRangeToList() { (1f..3f).toList() }
fun openDoubleRangeToList() { (1.0..<3.0).toList() }
fun openFloatRangeToList() { (1f..<3f).toList() }
fun inferredFloatingRange() {
    val range = 1.0..3.0
    range.toList()
    range.map { 1 }
    range.step(1)
}
