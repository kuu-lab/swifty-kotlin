// CANDIDATE-ONLY: collection constructors with mismatched arity or argument
// types must be compile errors, matching kotlinc overload resolution
// (KUU-4448). Compare the diagnostics with
// kuu4448_collection_ctor_reject.expected.stderr.
// NOTE: LinkedHashMap's JVM access-order ctor (Int, Float, Boolean) is a
// valid kotlinc call that KSwiftK does not declare yet — tracked separately
// as KUU-4500, so it is intentionally absent here.
fun main() {
    val a = HashMap<String, Int>("x", 1.5, true)
    val b = ArrayList<Int>("x", "y")
    val c = HashSet<Int>("x")
    val d = LinkedHashSet<Int>("x")
    val f = ArrayList<String>("x")
}
