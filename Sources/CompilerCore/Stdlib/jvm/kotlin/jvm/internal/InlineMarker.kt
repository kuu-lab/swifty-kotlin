@file:kotlin.jvm.JvmName("InlineMarker")
package kotlin.jvm.internal

public fun mark(index: Int) {}
public fun mark(name: String) {}
public fun beforeInlineCall() {}
public fun afterInlineCall() {}
public fun finallyStart(depth: Int) {}
public fun finallyEnd(depth: Int) {}
