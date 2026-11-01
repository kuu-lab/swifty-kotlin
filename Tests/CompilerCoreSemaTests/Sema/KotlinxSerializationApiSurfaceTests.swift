#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport
import TestStdlibCache

/// KUU-3919: the bundled stdlib ships the kotlinx.serialization API surface
/// that Ktor's common sources import (`Serializable`/`KSerializer`/
/// `descriptors`/`encoding`/`modules`/`serializer()`). The source below
/// mirrors `io.ktor.http.Url`'s `UrlSerializer`, `io.ktor.util.date.GMTDate`'s
/// `@Serializable` marker and `io.ktor.util.reflect.TypeInfo.serializer()`
/// (whose `serializer(it)` must fall through the inapplicable same-name
/// extension to the imported `serializer(KType)` overload).
@Suite
struct KotlinxSerializationApiSurfaceTests {
    @Test
    func ktorSerializerPatternsResolveAgainstBundledStdlib() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        import kotlinx.serialization.InternalSerializationApi
        import kotlinx.serialization.KSerializer
        import kotlinx.serialization.Serializable
        import kotlinx.serialization.builtins.nullable
        import kotlinx.serialization.descriptors.PrimitiveKind
        import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
        import kotlinx.serialization.descriptors.SerialDescriptor
        import kotlinx.serialization.encoding.Decoder
        import kotlinx.serialization.encoding.Encoder
        import kotlinx.serialization.modules.SerializersModule
        import kotlinx.serialization.serializer
        import kotlin.reflect.KClass
        import kotlin.reflect.KType

        class Url(val raw: String)

        @Serializable(with = UrlSerializer::class)
        class UrlHolder(val url: Url)

        object UrlSerializer : KSerializer<Url> {
            override val descriptor: SerialDescriptor =
                PrimitiveSerialDescriptor("io.ktor.http.Url", PrimitiveKind.STRING)
            override fun deserialize(decoder: Decoder): Url = Url(decoder.decodeString())
            override fun serialize(encoder: Encoder, value: Url) {
                encoder.encodeString(value.toString())
            }
        }

        @Serializable
        class GMTDate(val timestamp: Long)

        class TypeInfo(
            val type: KClass<*>,
            val isNullable: Boolean,
            val kotlinType: KType? = null,
        )

        @OptIn(InternalSerializationApi::class)
        fun TypeInfo.serializer(): KSerializer<out Any?> {
            val serializer = kotlinType?.let { serializer(it) } ?: type.serializer()
            return if (isNullable) (serializer as KSerializer<Any>).nullable else serializer
        }

        fun contextualLookup(module: SerializersModule): KSerializer<*>? =
            module.getContextual(Url::class)
        """
        let ctx = makeContextFromSources([source], allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
