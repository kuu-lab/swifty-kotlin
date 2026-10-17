@file:OptIn(kotlinx.io.UnsafeIoApi::class)

package kuu2603

import kotlinx.io.unsafe.UnsafeBufferOperations

fun preserveUnsafeBufferOperations(value: UnsafeBufferOperations): UnsafeBufferOperations = value
