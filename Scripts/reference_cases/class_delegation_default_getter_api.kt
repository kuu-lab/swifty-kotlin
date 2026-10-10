package delegation
interface Flag { val value: Boolean get() = false }
class DefaultFlag : Flag
class KnownFlag : Flag { override val value: Boolean get() = true }
open class Wrapped(private val original: Flag) : Flag by original
