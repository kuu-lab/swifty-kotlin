@file:OptIn(kotlinx.io.UnsafeIoApi::class)

package kuu2603

import kotlinx.io.unsafe.UnsafeBufferOperations

fun main() {
    val typedObject: UnsafeBufferOperations = unsafeBufferOperationsFromProducer()
    val returnedObject: UnsafeBufferOperations = preserveUnsafeBufferOperations(typedObject)
    check(typedObject === UnsafeBufferOperations)
    check(returnedObject === UnsafeBufferOperations)
    println("PASS:typed-object;identity=shared")
}
