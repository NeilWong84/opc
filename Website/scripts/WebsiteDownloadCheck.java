import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.URL;
import java.security.MessageDigest;
import javax.net.ssl.HttpsURLConnection;

/** Device-side HTTPS download acceptance check; uses Android's default TLS trust. */
public final class WebsiteDownloadCheck {
    public static void main(String[] args) throws Exception {
        if (args.length != 4 || !args[0].startsWith("https://www.opcapp.art/packages/")) {
            throw new IllegalArgumentException("Expected public OPC APK URL, device path, size and SHA-256");
        }
        HttpsURLConnection connection = (HttpsURLConnection) new URL(args[0]).openConnection();
        connection.setConnectTimeout(20000);
        connection.setReadTimeout(60000);
        if (connection.getResponseCode() != 200 || !connection.getContentType().contains("application/vnd.android.package-archive")) {
            throw new IllegalStateException("Unexpected HTTPS download response");
        }
        File file = new File(args[1]);
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        long total = 0;
        try (InputStream input = connection.getInputStream(); FileOutputStream output = new FileOutputStream(file)) {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
                digest.update(buffer, 0, count);
                total += count;
            }
        } finally {
            connection.disconnect();
        }
        StringBuilder hash = new StringBuilder();
        for (byte value : digest.digest()) hash.append(String.format("%02x", value & 255));
        if (total != Long.parseLong(args[2]) || !hash.toString().equals(args[3])) {
            throw new IllegalStateException("APK size or SHA-256 mismatch");
        }
        System.out.println("PASS Android default-trust HTTPS download: " + total + " bytes; SHA-256=" + hash);
    }
}
