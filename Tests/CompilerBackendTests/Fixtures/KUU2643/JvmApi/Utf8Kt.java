package kotlinx.io;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

public final class Utf8Kt {
    public static String readString(Source source, long byteCount) {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        for (long index = 0; index < byteCount; index++) {
            bytes.write(source.getBuffer().get(index));
        }
        source.skip(byteCount);
        return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
    }
}
