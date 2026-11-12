import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Stream;

public class ReadJDKClasses {
    private static final String PREFIX = "glob:**/";
    private static final String DIRECT_SUFFIX = "/*.class";
    private static final String RECURSIVE_SUFFIX = "/**/*.class";

    public static void main(String[] args) throws Exception {
        var runningImage = Path.of(System.getProperty("java.home"), "lib", "modules");
        if (!Files.isSameFile(runningImage, Path.of(args[1]))) {
            throw new IllegalArgumentException("The Java launcher belongs to a different runtime image.");
        }
        var image = FileSystems.getFileSystem(URI.create("jrt:/"));
        var packages = image.getPath("/packages");
        var modules = image.getPath("/modules");
        Set<String> direct = new HashSet<>();
        Set<String> recursive = new HashSet<>();
        Set<String> exact = new HashSet<>();
        Set<String> exactPackages = new HashSet<>();
        for (String pattern : args[0].split(",")) {
            if (!pattern.startsWith(PREFIX)) throw new IllegalArgumentException(pattern);
            String name = pattern.substring(PREFIX.length());
            if (name.endsWith(RECURSIVE_SUFFIX)) {
                recursive.add(packageName(name, name.length() - RECURSIVE_SUFFIX.length()));
            } else if (name.endsWith(DIRECT_SUFFIX)) {
                direct.add(packageName(name, name.length() - DIRECT_SUFFIX.length()));
            } else {
                exact.add(name);
                exactPackages.add(packageName(name, name.lastIndexOf('/')));
            }
        }

        Set<String> classes = new TreeSet<>();
        try (Stream<Path> packageEntries = Files.list(packages)) {
            for (Path pkg : (Iterable<Path>) packageEntries::iterator) {
                String name = pkg.getFileName().toString();
                boolean whole = direct.stream().anyMatch(p -> name.equals(p) || name.endsWith("." + p))
                    || recursive.stream().anyMatch(p -> name.startsWith(p + ".") || name.contains("." + p + "."));
                if (!whole && exactPackages.stream().noneMatch(p -> name.equals(p) || name.endsWith("." + p))) continue;
                String relative = name.replace('.', '/');
                try (Stream<Path> owners = Files.list(pkg)) {
                    for (Path owner : (Iterable<Path>) owners::iterator) {
                        var directory = modules.resolve(owner.getFileName()).resolve(relative);
                        try (Stream<Path> files = Files.list(directory)) {
                            for (Path entry : (Iterable<Path>) files::iterator) {
                                String className = entry.getFileName().toString();
                                String path = relative + "/" + className;
                                if (className.endsWith(".class") && (whole
                                    || exact.stream().anyMatch(p -> path.equals(p) || path.endsWith("/" + p)))) {
                                    classes.add(modules.relativize(entry).toString());
                                }
                            }
                        }
                    }
                }
            }
        }

        var output = new DataOutputStream(new BufferedOutputStream(System.out));
        output.writeInt(classes.size());
        for (String path : classes) {
            writeBytes(output, path.getBytes(StandardCharsets.UTF_8));
            writeBytes(output, Files.readAllBytes(modules.resolve(path)));
        }
        output.flush();
    }

    private static String packageName(String path, int end) {
        return path.substring(0, end).replace('/', '.');
    }

    private static void writeBytes(DataOutputStream output, byte[] bytes) throws Exception {
        output.writeInt(bytes.length);
        output.write(bytes);
    }
}
