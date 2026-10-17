import java.io.File
import kotlinx.io.files.Path

fun constructThroughInternalPathConstructor(): Path = Path(File("private"))
