import kotlinx.io.files.Path

fun constructThroughNativeInternalPathConstructor(): Path = Path("private", null)
