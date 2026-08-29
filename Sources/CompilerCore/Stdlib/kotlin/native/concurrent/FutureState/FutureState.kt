package kotlin.native.concurrent

@ObsoleteWorkersApi
public enum class FutureState(public val value: Int) {
    INVALID(0),
    SCHEDULED(1),
    COMPUTED(2),
    CANCELLED(3),
    THROWN(4)
}
