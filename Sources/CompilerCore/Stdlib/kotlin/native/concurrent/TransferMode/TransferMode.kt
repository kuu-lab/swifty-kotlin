package kotlin.native.concurrent

@ObsoleteWorkersApi
public enum class TransferMode(public val value: Int) {
    SAFE(0),
    UNSAFE(1)
}
