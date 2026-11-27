package kotlin

public class DeepRecursiveFunction<T, R>(
    block: suspend DeepRecursiveScope<T, R>.(T) -> R
)

public operator fun <T, R> DeepRecursiveFunction<T, R>.invoke(value: T): R = null!!

@kotlin.coroutines.RestrictsSuspension
public sealed class DeepRecursiveScope<T, R> {
    public abstract suspend fun callRecursive(value: T): R

    public abstract suspend fun <U, S> DeepRecursiveFunction<U, S>.callRecursive(value: U): S

    @Deprecated(
        level = DeprecationLevel.ERROR,
        message = "'invoke' should not be called from DeepRecursiveScope. Use 'callRecursive' to do recursion in the heap instead of the call stack.",
        replaceWith = ReplaceWith("this.callRecursive(value)")
    )
    public operator fun DeepRecursiveFunction<*, *>.invoke(value: Any?): Nothing = null!!
}
