#if os(macOS)
@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite(.serialized)
struct KotlinNativePosixFoundationExecutionTests {
    @Test
    func posixErrnoByteOrderAndFoundationCharsetRoundTrip() throws {
        TestStdlibCache.shared.prepare()
        let level = try #require(OptimizationLevel(rawValue: 0))
        try compileAndRunKotlin(
            """
            @file:Suppress("CAST_NEVER_SUCCEEDS")
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class,
                kotlinx.cinterop.ExperimentalForeignApi::class)

            import kotlin.experimental.*
            import kotlinx.cinterop.*
            import platform.Foundation.*
            import platform.posix.*

            fun main() {
                if (access("", F_OK) != -1 || errno != ENOENT) error("POSIX errno mismatch")
                println("errno=true")

                if (!Platform.isLittleEndian) error("Unexpected macOS byte order")
                println("little=true")

                val text = "Kotlin café 🍵"
                val bytes = text.encodeToByteArray()
                if (!byteArrayOf().isEmpty() || byteArrayOf(1).isEmpty()) error("ByteArray.isEmpty mismatch")
                println("byte-array-empty=true")

                val pointerSource = byteArrayOf(1, 2, 3)
                val pointerCopy = ByteArray(2)
                pointerSource.usePinned { sourcePinned ->
                    pointerCopy.usePinned { destinationPinned ->
                        memcpy(destinationPinned.addressOf(0), sourcePinned.addressOf(0) + 1L, 2uL)
                    }
                }
                if (pointerCopy[0] != 2.toByte() || pointerCopy[1] != 3.toByte()) {
                    error("Long C pointer arithmetic or memcpy mismatch")
                }
                println("pointer-add=true")

                val mutableData = NSMutableData()
                bytes.usePinned { mutableData.appendBytes(it.addressOf(0), bytes.size.toULong()) }
                val decoded = NSString.create(mutableData, NSUTF8StringEncoding)
                    ?: error("Foundation UTF-8 decode failed")
                if (decoded != text) error("Foundation UTF-8 decode changed bytes")

                val encoded = (text as? NSString)?.dataUsingEncoding(NSUTF8StringEncoding)
                    ?: error("Foundation UTF-8 encode failed")
                if (encoded.length != bytes.size.toULong()) error("Foundation UTF-8 length mismatch")
                println("utf8=true")
            }
            """,
            expectedOutput: "errno=true\nlittle=true\nbyte-array-empty=true\npointer-add=true\nutf8=true\n",
            allowDefaultStdlibLibrary: true,
            optLevel: level
        )
    }

    @Test
    func nsDataCompressionAndMutableDataCreateLengthRoundTrip() throws {
        TestStdlibCache.shared.prepare()
        let level = try #require(OptimizationLevel(rawValue: 0))
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

            import kotlinx.cinterop.*
            import platform.Foundation.*

            fun main() {
                val text = "Compress me, please!"
                val bytes = text.encodeToByteArray()

                val data = NSMutableData()
                bytes.usePinned { data.appendBytes(it.addressOf(0), bytes.size.toULong()) }

                val compressed = data.compressedDataUsingAlgorithm(
                    algorithm = NSDataCompressionAlgorithmZlib,
                    error = null
                )!!
                val hex = StringBuilder()
                val raw = compressed.bytes!!
                for (index in 0 until compressed.length.toInt()) {
                    val value = raw[index].toInt() and 0xFF
                    hex.append((value shr 4).toString(16)).append((value and 0xF).toString(16))
                }
                println("zlib-hex=${hex.toString() == "73cecf2d284a2d2e56c84dd55128c8494d2c4e550400"}")

                val decompressed = compressed.decompressedDataUsingAlgorithm(
                    algorithm = NSDataCompressionAlgorithmZlib,
                    error = null
                )!!
                println("roundtrip=${NSString.create(decompressed, NSUTF8StringEncoding) == text}")

                for (algorithm in listOf(NSDataCompressionAlgorithmLZFSE,
                                         NSDataCompressionAlgorithmLZ4,
                                         NSDataCompressionAlgorithmLZMA,
                                         NSDataCompressionAlgorithmZlib)) {
                    val packed = data.compressedDataUsingAlgorithm(algorithm = algorithm, error = null)
                    val unpacked = packed?.decompressedDataUsingAlgorithm(algorithm = algorithm, error = null)
                    println("algo-$algorithm=${packed != null && unpacked != null && unpacked.length == data.length.toULong()}")
                }

                val readData = NSMutableData.create(length = 100.convert())!!
                println("created=${readData.length == 100uL}")
                readData.appendBytes(compressed.bytes, compressed.length)
                println("appended=${readData.length == 100uL + compressed.length}")
            }
            """,
            expectedOutput: "zlib-hex=true\nroundtrip=true\n" +
                "algo-0=true\nalgo-1=true\nalgo-2=true\nalgo-3=true\n" +
                "created=true\nappended=true\n",
            allowDefaultStdlibLibrary: true,
            optLevel: level
        )
    }

    @Test
    func nsDateFormatterDefaultsTimeZoneLocaleUUIDAndLog() throws {
        TestStdlibCache.shared.prepare()
        let level = try #require(OptimizationLevel(rawValue: 0))
        try compileAndRunKotlin(
            """
            import platform.Foundation.*

            fun main() {
                // NSDate: unix epoch arithmetic, comparison, description.
                val epoch = NSDate.dateWithTimeIntervalSince1970(0.0)
                println("epoch-since1970=${epoch.timeIntervalSince1970 == 0.0}")
                println("epoch-ref=${epoch.timeIntervalSinceReferenceDate == -978307200.0}")
                val later = epoch.dateByAddingTimeInterval(60.0)
                println("add=${later.timeIntervalSince1970 == 60.0}")
                println("compare=${epoch.compare(later) == NSComparisonResultOrderedAscending}")
                println("earlier=${epoch.earlierDate(later).timeIntervalSince1970 == 0.0}")
                println("later-fn=${epoch.laterDate(later).timeIntervalSince1970 == 60.0}")
                println("interval=${later.timeIntervalSinceDate(epoch) == 60.0}")
                println("distant=${NSDate.distantPast.compare(NSDate.distantFuture) == NSComparisonResultOrderedAscending}")
                println("tostring=${epoch.toString().isNotEmpty()}")

                // NSDateFormatter: format/parse round-trip pinned to GMT.
                val formatter = NSDateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = NSTimeZone.timeZoneForSecondsFromGMT(0)
                println("format=${formatter.stringFromDate(epoch) == "1970-01-01"}")
                val parsed = formatter.dateFromString("1970-01-02")
                println("parsed=${parsed?.timeIntervalSince1970 == 86400.0}")
                formatter.dateStyle = NSDateFormatterMediumStyle
                formatter.timeStyle = NSDateFormatterShortStyle
                println("styles=${formatter.dateStyle == NSDateFormatterMediumStyle && formatter.timeStyle == NSDateFormatterShortStyle}")
                formatter.isLenient = true
                println("lenient=${formatter.isLenient}")
                val localized = NSDateFormatter.localizedStringFromDate(epoch, NSDateFormatterMediumStyle, NSDateFormatterShortStyle)
                println("localized=${localized.isNotEmpty()}")

                // NSTimeZone: named lookup, offsets, local zone sanity.
                val tokyo = NSTimeZone.timeZoneWithName("Asia/Tokyo")!!
                println("tz=${tokyo.secondsFromGMT == 32400L && tokyo.name == "Asia/Tokyo"}")
                val local = NSTimeZone.localTimeZone
                println("tz-local=${local.name.isNotEmpty() && local.isEqualToTimeZone(NSTimeZone.systemTimeZone)}")
                println("tz-date=${NSTimeZone.timeZoneForSecondsFromGMT(0).secondsFromGMTForDate(epoch) == 0L}")
                println("tz-null=${NSTimeZone.timeZoneWithName("KUU4036/NotAZone") == null}")
                println("tz-fixed=${NSTimeZone.timeZoneForSecondsFromGMT(3600).secondsFromGMT == 3600L}")

                // NSLocale + NSUUID.
                val locale = NSLocale.localeWithLocaleIdentifier("en_US")
                println("locale=${locale.localeIdentifier.startsWith("en") && locale.languageCode == "en"}")
                println("locale-current=${NSLocale.currentLocale.localeIdentifier.isNotEmpty()}")
                val uuid = NSUUID.UUID()
                println("uuid=${uuid.UUIDString.length == 36}")

                // NSUserDefaults suite: scalar/object round-trips, removal,
                // registered defaults, dictionary representation.
                val defaults = NSUserDefaults("KSwiftK-Test-" + NSUUID().UUIDString)
                defaults.setInteger(42L, forKey = "answer")
                defaults.setBool(true, forKey = "flag")
                defaults.setDouble(2.5, forKey = "ratio")
                defaults.setObject("hello", forKey = "greeting")
                defaults.setObject(listOf("a", 7, true), forKey = "items")
                println("int=${defaults.integerForKey("answer") == 42L}")
                println("bool=${defaults.boolForKey("flag")}")
                println("double=${defaults.doubleForKey("ratio") == 2.5}")
                println("str=${defaults.stringForKey("greeting") == "hello"}")
                println("obj=${defaults.objectForKey("greeting") == "hello"}")
                println("missing=${defaults.objectForKey("absent") == null}")
                val items = defaults.objectForKey("items")
                println("items=${items is List<*> && items.size == 3 && items[1] == 7L && items[2] == true}")
                defaults.setObject(mapOf("inner" to 9), forKey = "lookup")
                val lookup = defaults.objectForKey("lookup")
                println("map=${lookup is Map<*, *> && lookup.size == 1 && lookup.values.first() == 9L}")
                defaults.removeObjectForKey("greeting")
                println("removed=${defaults.objectForKey("greeting") == null}")
                defaults.registerDefaults(mapOf<Any?, Any?>("fallback" to "yes"))
                println("registered=${defaults.stringForKey("fallback") == "yes" && !defaults.objectIsForcedForKey("fallback")}")
                println("dict=${defaults.dictionaryRepresentation().containsKey("answer")}")
                println("synchronize-type=${defaults.synchronize() is Boolean}")

                // NSLog + NSThread conveniences must run without trapping.
                NSLog("KUU4036 probe %d %@", 7, "args")
                val isMain: Boolean = NSThread.isMainThread()
                println("thread-stack=${NSThread.callStackSymbols.isNotEmpty()}")
                NSThread.sleepForTimeInterval(0.001)
                println("done")
            }
            """,
            expectedOutput: "epoch-since1970=true\n" +
                "epoch-ref=true\n" +
                "add=true\n" +
                "compare=true\n" +
                "earlier=true\n" +
                "later-fn=true\n" +
                "interval=true\n" +
                "distant=true\n" +
                "tostring=true\n" +
                "format=true\n" +
                "parsed=true\n" +
                "styles=true\n" +
                "lenient=true\n" +
                "localized=true\n" +
                "tz=true\n" +
                "tz-local=true\n" +
                "tz-date=true\n" +
                "tz-null=true\n" +
                "tz-fixed=true\n" +
                "locale=true\n" +
                "locale-current=true\n" +
                "uuid=true\n" +
                "int=true\n" +
                "bool=true\n" +
                "double=true\n" +
                "str=true\n" +
                "obj=true\n" +
                "missing=true\n" +
                "items=true\n" +
                "map=true\n" +
                "removed=true\n" +
                "registered=true\n" +
                "dict=true\n" +
                "synchronize-type=true\n" +
                "thread-stack=true\n" +
                "done\n",
            allowDefaultStdlibLibrary: true,
            optLevel: level
        )
    }
}
#endif
