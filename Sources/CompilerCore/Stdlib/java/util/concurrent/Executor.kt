package java.util.concurrent

import java.lang.Runnable

public fun interface Executor {
    public fun execute(command: Runnable)
}
