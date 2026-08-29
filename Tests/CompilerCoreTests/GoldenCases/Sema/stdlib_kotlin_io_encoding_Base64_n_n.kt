package golden.sema

import kotlin.enums.EnumEntries
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

@OptIn(ExperimentalEncodingApi::class)
fun defaultObject(): Base64.Default = Base64.Default

@OptIn(ExperimentalEncodingApi::class)
fun base64Type(): Base64 = Base64.Default

@OptIn(ExperimentalEncodingApi::class)
fun paddingEntries(): EnumEntries<Base64.PaddingOption> = Base64.PaddingOption.entries
