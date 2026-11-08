package java.security

public open class Provider(
    public val name: String,
    public val version: Double,
    public val info: String,
) {
    public fun getVersionStr(): String = version.toString()
}

internal val bundledJcaProvider = Provider("KSwiftK", 1.0, "Bundled KSwiftK JCA provider")
