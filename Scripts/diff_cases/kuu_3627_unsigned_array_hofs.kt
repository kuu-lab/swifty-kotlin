// KUU-3627: indexOf, forEachIndexed, max, min, maxOrNull and minOrNull used to
// resolve only on UIntArray (SEMA-0024 on ULongArray/UByteArray/UShortArray).
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val ul = ulongArrayOf(1uL, 3uL, 2uL)
    println("ulong max=${ul.max()}")
    println("ulong min=${ul.min()}")
    println("ulong maxOrNull=${ul.maxOrNull()}")
    println("ulong minOrNull=${ul.minOrNull()}")
    println("ulong indexOf=${ul.indexOf(3uL)}")
    println("ulong indexOfMiss=${ul.indexOf(9uL)}")
    ul.forEachIndexed { i, v -> println("ulong[$i]=$v") }
    println("ulong empty=${ulongArrayOf().maxOrNull()},${ulongArrayOf().minOrNull()},${ulongArrayOf().indexOf(1uL)}")

    val ub = ubyteArrayOf(1u, 3u, 2u)
    println("ubyte max=${ub.max()}")
    println("ubyte min=${ub.min()}")
    println("ubyte maxOrNull=${ub.maxOrNull()}")
    println("ubyte minOrNull=${ub.minOrNull()}")
    println("ubyte indexOf=${ub.indexOf(3u)}")
    println("ubyte indexOfMiss=${ub.indexOf(9u)}")
    ub.forEachIndexed { i, v -> println("ubyte[$i]=$v") }
    println("ubyte empty=${ubyteArrayOf().maxOrNull()},${ubyteArrayOf().minOrNull()},${ubyteArrayOf().indexOf(1u)}")

    val us = ushortArrayOf(1u, 3u, 2u)
    println("ushort max=${us.max()}")
    println("ushort min=${us.min()}")
    println("ushort maxOrNull=${us.maxOrNull()}")
    println("ushort minOrNull=${us.minOrNull()}")
    println("ushort indexOf=${us.indexOf(3u)}")
    println("ushort indexOfMiss=${us.indexOf(9u)}")
    us.forEachIndexed { i, v -> println("ushort[$i]=$v") }
    println("ushort empty=${ushortArrayOf().maxOrNull()},${ushortArrayOf().minOrNull()},${ushortArrayOf().indexOf(1u)}")

    // UIntArray control: the same calls resolved before the fix.
    val ui = uintArrayOf(1u, 3u, 2u)
    println("uint max=${ui.max()}")
    println("uint min=${ui.min()}")
    println("uint maxOrNull=${ui.maxOrNull()}")
    println("uint minOrNull=${ui.minOrNull()}")
    println("uint indexOf=${ui.indexOf(3u)}")
    ui.forEachIndexed { i, v -> println("uint[$i]=$v") }
}
