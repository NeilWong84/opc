package jp.opc.opc_app

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/** 系统逐页 PDF 渲染，临时文件只在应用 cache 内；不加载网络或执行文档脚本。 */
class DocumentPreview(private val cache: File) {
    private data class Document(val file: File, val renderer: PdfRenderer)
    private val documents = mutableMapOf<String, Document>()

    @Synchronized fun handle(method: String, args: Map<*, *>, result: MethodChannel.Result) {
        try {
            when (method) {
                "open" -> {
                    val bytes = args["bytes"] as ByteArray
                    require(bytes.size in 5..(50 * 1024 * 1024))
                    val file = File.createTempFile("opc-pdf-", ".pdf", cache)
                    try {
                        file.writeBytes(bytes)
                        val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        val renderer = try { PdfRenderer(descriptor) } catch (error: Exception) {
                            descriptor.close(); throw error
                        }
                        if (renderer.pageCount !in 1..5000) { renderer.close(); error("Invalid page count") }
                        val handle = UUID.randomUUID().toString()
                        documents[handle] = Document(file, renderer)
                        result.success(mapOf("handle" to handle, "pages" to renderer.pageCount))
                    } catch (error: Exception) { file.delete(); throw error }
                }
                "page" -> {
                    val document = requireNotNull(documents[args["handle"] as String])
                    val index = (args["page"] as Number).toInt()
                    require(index in 0 until document.renderer.pageCount)
                    document.renderer.openPage(index).use { page ->
                        val width = (args["width"] as Number).toInt().coerceIn(320, 2000)
                        val height = (width.toDouble() * page.height / page.width).toInt().coerceIn(1, 4000)
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            ByteArrayOutputStream().use { output ->
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                                result.success(output.toByteArray())
                            }
                        } finally { bitmap.recycle() }
                    }
                }
                "close" -> { close(args["handle"] as String); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("document_preview_failed", "Document cannot be rendered", null)
        }
    }

    private fun close(handle: String) {
        documents.remove(handle)?.let { document ->
            try { document.renderer.close() } finally { document.file.delete() }
        }
    }

    @Synchronized fun closeAll() { documents.keys.toList().forEach { close(it) } }
}
