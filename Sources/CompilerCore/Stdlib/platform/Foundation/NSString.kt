package platform.Foundation

// Kotlin strings are the value representation behind the Foundation string bridge.
public typealias NSString = String
public typealias NSStringEncoding = ULong

public const val NSASCIIStringEncoding: NSStringEncoding = 1uL
public const val NSNEXTSTEPStringEncoding: NSStringEncoding = 2uL
public const val NSJapaneseEUCStringEncoding: NSStringEncoding = 3uL
public const val NSUTF8StringEncoding: NSStringEncoding = 4uL
public const val NSISOLatin1StringEncoding: NSStringEncoding = 5uL
public const val NSUTF16StringEncoding: NSStringEncoding = 10uL
public const val NSUTF16BigEndianStringEncoding: NSStringEncoding = 0x90000100uL
public const val NSUTF16LittleEndianStringEncoding: NSStringEncoding = 0x94000100uL
public const val NSUTF32StringEncoding: NSStringEncoding = 0x8c000100uL
public const val NSUTF32BigEndianStringEncoding: NSStringEncoding = 0x98000100uL
public const val NSUTF32LittleEndianStringEncoding: NSStringEncoding = 0x9c000100uL

public fun String.dataUsingEncoding(encoding: NSStringEncoding): NSData? =
    __foundation_string_data_using_encoding(this, encoding)?.let { NSData(it) }

public fun String.Companion.create(data: NSData, encoding: NSStringEncoding): String? =
    __foundation_string_from_data(data.__handle, encoding)
