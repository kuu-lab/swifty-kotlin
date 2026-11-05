package platform.Foundation

/**
 * NSLog(format:...) — the variadic arguments are forwarded to the runtime,
 * which expands the printf-style format against real Foundation objects.
 */
public fun NSLog(format: String, vararg arguments: Any?) {
    __foundation_nslog(format, arguments)
}
