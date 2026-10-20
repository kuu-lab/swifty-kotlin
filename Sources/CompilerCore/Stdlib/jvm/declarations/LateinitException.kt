package kotlin
open class UninitializedPropertyAccessException: RuntimeException { constructor(): super(); constructor(message: String?): super(message) }
