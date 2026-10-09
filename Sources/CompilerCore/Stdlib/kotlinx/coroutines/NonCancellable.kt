package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext

// The synthetic registry binds this object to a raw runtime Job handle via
// kk_non_cancellable_instance. Custom getters avoid stored fields on that handle;
// the object initializer registers its interface dispatch without allocating
// a second singleton or running AbstractCoroutineContextElement's constructor.

public object NonCancellable : AbstractCoroutineContextElement(Job), Job {
    override val key: CoroutineContext.Key<*> get() = Job
    override val isActive: Boolean get() = true
    override val isCompleted: Boolean get() = false
    override val isCancelled: Boolean get() = false
    override fun toString(): String = "NonCancellable"
}

/** Compatibility alias for the Job context key. */
public val NonCancellable.Key: CoroutineContext.Key<Job>
    get() = Job

/** Upstream `NonCancellable.parent` is always `null`. */
public val NonCancellable.parent: Job?
    get() = null

/** Upstream `NonCancellable.children` is always empty. */
public val NonCancellable.children: Sequence<Job>
    get() = emptySequence()
