package platform.Foundation

public open class NSUUID internal constructor(handle: Long) : NSObject(handle) {
    public constructor() : this(__foundation_uuid_create())

    public val UUIDString: String
        get() = __foundation_uuid_string(__handle)

    public companion object {}
}

public fun NSUUID.Companion.UUID(): NSUUID = NSUUID()
