import kotlinx.io.files.Path

fun constructThroughInternalPathConstructor(): Path = Path("private", true)
