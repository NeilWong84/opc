package jp.opc.opc_app

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private lateinit var referenceChannel: MethodChannel
    private val expectedSizes = mutableMapOf<String, Long>()
    private var pendingExport: Pair<String, MethodChannel.Result>? = null
    private val exportRequest = 7401
    private var documentPreview: DocumentPreview? = null
    private val referenceDirectory: File
        get() = File(filesDir, "reference_downloads").apply { mkdirs() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val documents = DocumentPreview(cacheDir)
        documentPreview = documents
        val documentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "opc/document_preview", StandardMethodCodec.INSTANCE,
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue())
        documentChannel.setMethodCallHandler { call, result ->
            documents.handle(call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
        }
        referenceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "opc/reference_files")
        referenceChannel.setMethodCallHandler { call, result ->
            try {
                handleReference(call, result)
            } catch (error: Exception) {
                result.error("reference_file_error", error.message, null)
            }
        }
    }

    private fun safeName(value: String): String {
        require(value.isNotBlank() && value != "." && value != "..") { "Invalid filename" }
        require(!value.any { it == '/' || it == '\\' || it.code < 32 }) { "Invalid filename" }
        return value.take(160).replace(Regex("[<>:\"|?*]"), "_")
    }

    private fun localFile(handle: String, partial: Boolean = false): File {
        require(Regex("^[a-f0-9-]{36}_.+").matches(handle)) { "Invalid file handle" }
        require(!handle.any { it == '/' || it == '\\' || it.code < 32 } && !handle.endsWith(".part")) { "Invalid file handle" }
        val base = referenceDirectory.canonicalFile
        val file = File(base, handle + if (partial) ".part" else "").canonicalFile
        require(file.parentFile == base) { "Invalid file path" }
        return file
    }

    private fun authorize(handle: String, result: MethodChannel.Result, action: () -> Unit) {
        referenceChannel.invokeMethod("authorize", handle, object : MethodChannel.Result {
            override fun success(value: Any?) {
                if (value == true) {
                    try { action() } catch (error: Exception) {
                        result.error("reference_file_error", error.message, null)
                    }
                } else result.error("reference_access_denied", "Reference access has changed", null)
            }
            override fun error(code: String, message: String?, details: Any?) {
                result.error("reference_access_denied", "Reference access has changed", null)
            }
            override fun notImplemented() {
                result.error("reference_access_denied", "Reference access cannot be verified", null)
            }
        })
    }

    private fun handleReference(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "begin" -> {
                val name = safeName(requireNotNull(call.argument<String>("fileName")))
                val total = requireNotNull(call.argument<Number>("totalBytes")).toLong()
                require(total in 1..100_000_000) { "Invalid reference size" }
                val handle = "${UUID.randomUUID()}_$name"
                val file = localFile(handle, true)
                require(file.createNewFile()) { "Could not create reference file" }
                expectedSizes[handle] = total
                result.success(handle)
            }
            "append" -> {
                val handle = requireNotNull(call.argument<String>("handle"))
                val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                val expected = requireNotNull(expectedSizes[handle])
                val file = localFile(handle, true)
                require(file.isFile && file.length() + bytes.size <= expected) { "Unexpected byte count" }
                FileOutputStream(file, true).use { it.write(bytes) }
                result.success(null)
            }
            "finish" -> {
                val handle = requireNotNull(call.argument<String>("handle"))
                val total = requireNotNull(call.argument<Number>("totalBytes")).toLong()
                val part = localFile(handle, true)
                require(expectedSizes[handle] == total && part.length() == total) { "Incomplete reference file" }
                FileOutputStream(part, true).use { it.fd.sync() }
                require(part.renameTo(localFile(handle))) { "Could not complete reference file" }
                expectedSizes.remove(handle)
                result.success(null)
            }
            "remove" -> {
                val handle = requireNotNull(call.argument<String>("handle"))
                localFile(handle, true).delete()
                localFile(handle).delete()
                expectedSizes.remove(handle)
                result.success(null)
            }
            "open" -> {
                val handle = requireNotNull(call.argument<String>("handle"))
                val mime = requireNotNull(call.argument<String>("mimeType"))
                authorize(handle, result) {
                    val file = localFile(handle)
                    require(file.isFile && file.length() > 0) { "Reference file is missing" }
                    val uri = FileProvider.getUriForFile(this, "$packageName.reference_files", file)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime)
                        clipData = ClipData.newRawUri(file.name, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(true)
                }
            }
            "export" -> {
                require(pendingExport == null) { "An export chooser is already open" }
                val handle = requireNotNull(call.argument<String>("handle"))
                val name = safeName(requireNotNull(call.argument<String>("fileName")))
                val mime = requireNotNull(call.argument<String>("mimeType"))
                authorize(handle, result) {
                    require(localFile(handle).isFile) { "Reference file is missing" }
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mime
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    startActivityForResult(intent, exportRequest)
                    pendingExport = handle to result
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequest) return
        val pending = pendingExport ?: return
        pendingExport = null
        val (handle, result) = pending
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        authorize(handle, result) {
            val source = localFile(handle)
            require(source.isFile && source.length() > 0) { "Reference file is missing" }
            val output = requireNotNull(contentResolver.openOutputStream(uri, "wt"))
            output.use { target -> source.inputStream().use { it.copyTo(target) }; target.flush() }
            result.success(true)
        }
    }

    override fun onDestroy() {
        documentPreview?.closeAll()
        pendingExport?.second?.success(false)
        pendingExport = null
        super.onDestroy()
    }
}
