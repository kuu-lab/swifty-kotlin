package kotlin

import kswiftk.internal.*

fun synchronized(lock: Any, block: () -> Any?): Any = __synchronized(lock, block)
