package kotlin

public open class UninitializedPropertyAccessException: RuntimeException {
    public constructor(): super()
    public constructor(message: String?): super(message)
}
