package platform.Foundation
public const val NSLocalizedDescriptionKey: String = "NSLocalizedDescription"
public const val NSUnderlyingErrorKey: String = "NSUnderlyingError"
public class NSError internal constructor(handle: Long) : NSObject(handle) {
    public constructor(domain: String, code: Long, userInfo: Map<Any?, *>?) : this(
        __foundation_error_create(domain, code,
            userInfo?.get(NSLocalizedDescriptionKey) as? String,
            userInfo?.get(NSUnderlyingErrorKey)))
    public val localizedDescription: String get() = __foundation_error_description(__handle)
}
public class NSURL internal constructor(handle: Long) : NSObject(handle) {
    public companion object {
        public fun fileURLWithPath(path: String): NSURL = NSURL(__foundation_url_file(path))
    }
}
