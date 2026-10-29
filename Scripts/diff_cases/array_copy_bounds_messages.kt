// Exception type and message parity for array copy helpers. `copyInto`
// delegates to `System.arraycopy` on the JVM, so each bounds failure
// reports the JDK arraycopy diagnostic naming the storage element type.
fun probe(name: String, f: () -> Any?) {
    try {
        println("$name -> [${f()}]")
    } catch (e: Exception) {
        println("$name -> ${e::class.simpleName}: ${e.message}")
    }
}

fun main() {
    probe("copyOf.-1") { arrayOf(1, 2, 3).copyOf(-1).toList() }
    probe("ia.copyOf.-1") { intArrayOf(1, 2, 3).copyOf(-1).toList() }
    probe("la.copyOf.-1") { longArrayOf(1L).copyOf(-1).toList() }

    probe("copyInto.dstOob") { val d = arrayOf(0, 0); arrayOf(1, 2, 3).copyInto(d, 1); d.toList() }
    probe("copyInto.dstNeg") { val d = arrayOf(0, 0); arrayOf(1).copyInto(d, -1); d.toList() }
    probe("copyInto.srcNeg") { val d = arrayOf(0, 0, 0); arrayOf(1, 2, 3).copyInto(d, 0, -1, 2); d.toList() }
    probe("copyInto.srcOob") { val d = arrayOf(0, 0, 0); arrayOf(1, 2, 3).copyInto(d, 0, 0, 5); d.toList() }
    probe("copyInto.negLen") { val d = arrayOf(0, 0, 0); arrayOf(1, 2, 3).copyInto(d, 0, 2, 1); d.toList() }
    probe("copyInto.ok") { val d = arrayOf(0, 0, 0); arrayOf(1, 2).copyInto(d, 1); d.toList() }

    probe("ia.copyInto.dstOob") { val d = intArrayOf(0, 0); intArrayOf(1, 2, 3).copyInto(d, 1); d.toList() }
    probe("ia.copyInto.srcNeg") { val d = intArrayOf(0, 0); intArrayOf(1, 2, 3).copyInto(d, 0, -1, 2); d.toList() }
    probe("la.copyInto.srcNeg") { val d = longArrayOf(0); longArrayOf(1).copyInto(d, 0, -1, 1); d.toList() }
    probe("ba.copyInto.srcNeg") { val d = byteArrayOf(0); byteArrayOf(1).copyInto(d, 0, -1, 1); d.toList() }
    probe("ca.copyInto.srcNeg") { val d = charArrayOf(' '); charArrayOf('a').copyInto(d, 0, -1, 1); d.toList() }
    probe("sa.copyInto.srcNeg") { val d = shortArrayOf(0); shortArrayOf(1).copyInto(d, 0, -1, 1); d.toList() }
    probe("fa.copyInto.srcNeg") { val d = floatArrayOf(0f); floatArrayOf(1f).copyInto(d, 0, -1, 1); d.toList() }
    probe("da.copyInto.srcNeg") { val d = doubleArrayOf(0.0); doubleArrayOf(1.0).copyInto(d, 0, -1, 1); d.toList() }
    probe("bla.copyInto.srcNeg") { val d = booleanArrayOf(false); booleanArrayOf(true).copyInto(d, 0, -1, 1); d.toList() }

    probe("uia.copyInto.srcNeg") { val d = uintArrayOf(0u); uintArrayOf(1u).copyInto(d, 0, -1, 1); d.toList() }
    probe("ula.copyInto.srcNeg") { val d = ulongArrayOf(0uL); ulongArrayOf(1uL).copyInto(d, 0, -1, 1); d.toList() }
    probe("uba.copyInto.srcNeg") { val d = ubyteArrayOf(0u); ubyteArrayOf(1u).copyInto(d, 0, -1, 1); d.toList() }
    probe("usa.copyInto.srcNeg") { val d = ushortArrayOf(0u); ushortArrayOf(1u).copyInto(d, 0, -1, 1); d.toList() }
}
