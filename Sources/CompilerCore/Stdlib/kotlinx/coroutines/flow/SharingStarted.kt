/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/SharingStarted.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

public enum class SharingCommand {
    START,
    STOP,
    STOP_AND_RESET_REPLAY_CACHE
}

public interface SharingStarted {
    public fun command(subscriptionCount: StateFlow<Int>): Flow<SharingCommand>

    public companion object {
        public val Eagerly: SharingStarted
            get() = StartedEagerly()
        public val Lazily: SharingStarted
            get() = StartedLazily()

        public fun WhileSubscribed(
            stopTimeoutMillis: Long = 0L,
            replayExpirationMillis: Long = Long.MAX_VALUE
        ): SharingStarted = StartedWhileSubscribed(stopTimeoutMillis, replayExpirationMillis)
    }
}

private class StartedEagerly : SharingStarted {
    override fun command(subscriptionCount: StateFlow<Int>): Flow<SharingCommand> =
        flowOf(SharingCommand.START)
}

internal fun SharingStarted.isEagerly(): Boolean = this is StartedEagerly

private class StartedLazily : SharingStarted {
    override fun command(subscriptionCount: StateFlow<Int>): Flow<SharingCommand> = flow {
        var started = false
        subscriptionCount.collect { count ->
            if (count > 0 && !started) {
                started = true
                emit(SharingCommand.START)
            }
        }
    }
}

private class StartedWhileSubscribed(
    private val stopTimeoutMillis: Long,
    private val replayExpirationMillis: Long
) : SharingStarted {
    init {
        require(stopTimeoutMillis >= 0L)
        require(replayExpirationMillis >= 0L)
    }

    override fun command(subscriptionCount: StateFlow<Int>): Flow<SharingCommand> = channelFlow {
        var hasSubscribers = false
        var pendingStop: Job? = null
        subscriptionCount.collect { count ->
            if (count > 0) {
                pendingStop?.cancel()
                pendingStop = null
                if (!hasSubscribers) send(SharingCommand.START)
                hasSubscribers = true
            } else if (hasSubscribers) {
                hasSubscribers = false
                pendingStop?.cancel()
                pendingStop = launch {
                    if (stopTimeoutMillis > 0L) delay(stopTimeoutMillis)
                    if (replayExpirationMillis > 0L) {
                        send(SharingCommand.STOP)
                        if (replayExpirationMillis < Long.MAX_VALUE) {
                            delay(replayExpirationMillis)
                            send(SharingCommand.STOP_AND_RESET_REPLAY_CACHE)
                        }
                    } else {
                        send(SharingCommand.STOP_AND_RESET_REPLAY_CACHE)
                    }
                }
            }
        }
    }
}
