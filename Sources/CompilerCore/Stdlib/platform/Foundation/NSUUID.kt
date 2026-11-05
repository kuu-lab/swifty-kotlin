package platform.Foundation

public open class NSUUID internal constructor(handle: Long) : NSObject(handle) {
    /** -[NSUUID init]: a new random UUID. */
    public constructor() : this(__foundation_uuid_create())

    public val UUIDString: String
        get() = __foundation_uuid_string(__handle)

    public companion object {}
}

/** +[NSUUID UUID]: a new random UUID. */
public fun NSUUID.Companion.UUID(): NSUUID = NSUUID()
