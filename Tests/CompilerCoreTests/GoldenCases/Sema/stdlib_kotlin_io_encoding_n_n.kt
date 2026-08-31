package golden.sema

import kotlin.io.encoding.ExperimentalEncodingApi

@ExperimentalEncodingApi
fun experimentalEncodingApiSurface(): String = "ok"

@OptIn(ExperimentalEncodingApi::class)
fun useExperimentalEncodingApiSurface(): String = experimentalEncodingApiSurface()
