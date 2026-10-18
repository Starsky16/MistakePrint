package com.starksky16.mistake_print

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES20
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 相册通道（Dart 侧 GalleryStore / ShareService 调用）：
 *  - ensureWritePermission：API 24–28 写公共相册需要的运行时权限（29+ 直接 true）
 *  - save              ：把出图 PNG 写入系统相册 Pictures/MistakePrint/
 *  - list              ：列出本应用写入相册的图片（写入时间倒序）
 *  - read              ：按媒体 uri 读回字节（供预览）
 *  - delete / deleteAll：删除相册里本应用的图片（同时删除媒体库记录与实体文件）
 *  - share             ：ACTION_SEND + 系统 chooser（不 setPackage，保持通用）
 *  - maxTextureSize    ：查询 GPU 最大纹理边长 GL_MAX_TEXTURE_SIZE（离屏出图的
 *    超采样档位约束用；失败返回 null，Dart 侧回落常数 4096）
 *
 * 删除说明：`content://media/...` 条目即媒体库记录本身，ContentResolver.delete 由
 * MediaProvider 一次完成「删记录 + 删文件」，不会留下死链或孤儿文件；本应用只删
 * 自己写入的条目（owner 限定），删除非本应用条目会被系统拒绝并转为明确报错。
 */
class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "mistake_print/gallery"
        private const val ALBUM_DIR = "Pictures/MistakePrint"
        private const val ALBUM_NAME = "MistakePrint"
        private const val REQ_WRITE = 101
        private const val MIME_PNG = "image/png"
    }

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensureWritePermission" -> ensureWritePermission(result)
            "save" -> {
                val name = call.argument<String>("name")
                val bytes = call.argument<ByteArray>("bytes")
                if (name == null || bytes == null) {
                    result.error("bad_args", "缺少参数", null)
                } else {
                    runAsync(result, "save_failed") { saveToGallery(name, bytes) }
                }
            }
            "list" -> runAsync(result, "list_failed") { listImages() }
            "read" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) {
                    result.error("bad_args", "缺少参数", null)
                } else {
                    runAsync(result, "read_failed") { readBytes(uri) }
                }
            }
            "delete" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) {
                    result.error("bad_args", "缺少参数", null)
                } else {
                    runAsync(result, "delete_failed") { deleteImage(uri); true }
                }
            }
            "deleteAll" -> runAsync(result, "delete_failed") { deleteAllImages() }
            "share" -> {
                val uri = call.argument<String>("uri")
                val mime = call.argument<String>("mimeType") ?: MIME_PNG
                if (uri == null) {
                    result.error("bad_args", "缺少参数", null)
                } else {
                    try {
                        result.success(shareImage(uri, mime))
                    } catch (e: Exception) {
                        result.error("share_failed", e.message ?: "分享失败", null)
                    }
                }
            }
            "maxTextureSize" -> result.success(queryMaxTextureSize())
            else -> result.notImplemented()
        }
    }

    // ===== 权限（仅 API 24–28 需要）=====

    private fun ensureWritePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            result.success(true) // 29+ 写本应用媒体无需权限
            return
        }
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQ_WRITE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_WRITE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }

    // ===== 写相册 =====

    private fun saveToGallery(name: String, bytes: ByteArray): Map<String, Any?> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveQ(name, bytes)
        } else {
            saveLegacy(name, bytes)
        }

    /** Android 10+：MediaStore.Images + RELATIVE_PATH，写本应用图片无需任何权限。 */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveQ(name: String, bytes: ByteArray): Map<String, Any?> {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME_PNG)
            put(MediaStore.MediaColumns.RELATIVE_PATH, ALBUM_DIR)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection =
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("无法在系统相册创建文件")
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("无法打开相册输出流")
            val done = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            if (contentResolver.update(uri, done, null, null) <= 0) {
                throw IllegalStateException("无法提交相册文件")
            }
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null) // 失败不留空壳/半截文件
            throw e
        }
        return describe(uri)
    }

    /** Android 9 及以下：写公共 Pictures 目录 + MediaScanner 入库（需写权限）。 */
    @Suppress("DEPRECATION")
    private fun saveLegacy(name: String, bytes: ByteArray): Map<String, Any?> {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            ALBUM_NAME,
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建相册目录")
        }
        val file = File(dir, name)
        try {
            file.outputStream().use { it.write(bytes) }
            // 让系统媒体库收录，用户在图库里才能看到；扫描是异步的，用 latch 等回调。
            val latch = CountDownLatch(1)
            var scanned: Uri? = null
            MediaScannerConnection.scanFile(
                this,
                arrayOf(file.absolutePath),
                arrayOf(MIME_PNG),
            ) { _, uri ->
                scanned = uri
                latch.countDown()
            }
            latch.await(5, TimeUnit.SECONDS)
            val uri = scanned
                ?: throw IllegalStateException("系统媒体库未收录该图片")
            return describe(uri)
        } catch (e: Exception) {
            file.delete() // 失败路径清掉孤儿文件，不在磁盘上留图库里看不见的占盘文件
            throw e
        }
    }

    /** 读回某条媒体记录的名字/大小/时间，组装成 Dart 侧要的 Map。 */
    private fun describe(uri: Uri): Map<String, Any?> {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_ADDED,
        )
        contentResolver.query(uri, projection, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                return mapOf(
                    "id" to c.getLong(0).toString(),
                    "uri" to uri.toString(),
                    "name" to (c.getString(1) ?: ""),
                    "size" to c.getLong(2),
                    "date" to c.getLong(3) * 1000L, // 秒 -> 毫秒
                )
            }
        }
        throw IllegalStateException("无法读取相册文件信息")
    }

    // ===== 列相册 =====

    /**
     * 本应用相册目录过滤；Android 11+ 再叠加 owner 过滤（30+ 才有该列），即使
     * 用户往同目录放过别的应用的图，也绝不混进列表、更不会被本应用删掉。
     */
    private fun listImages(): List<Map<String, Any?>> {
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            clauses.add("${MediaStore.MediaColumns.RELATIVE_PATH} = ?")
            args.add("$ALBUM_DIR/")
        } else {
            clauses.add("${MediaStore.MediaColumns.DATA} LIKE ?")
            args.add("%/$ALBUM_NAME/%")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            clauses.add("${MediaStore.MediaColumns.OWNER_PACKAGE_NAME} = ?")
            args.add(packageName)
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_ADDED,
        )
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            clauses.joinToString(" AND "),
            args.toTypedArray(),
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                out += mapOf(
                    "id" to id.toString(),
                    "uri" to ContentUris
                        .withAppendedId(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            id,
                        )
                        .toString(),
                    "name" to (c.getString(1) ?: ""),
                    "size" to c.getLong(2),
                    "date" to c.getLong(3) * 1000L,
                )
            }
        }
        return out
    }

    private fun readBytes(uriStr: String): ByteArray =
        contentResolver.openInputStream(Uri.parse(uriStr))?.use { it.readBytes() }
            ?: throw IllegalStateException("无法读取相册图片")

    private fun deleteImage(uriStr: String) {
        try {
            contentResolver.delete(Uri.parse(uriStr), null, null)
        } catch (e: SecurityException) {
            // 29+ 删除非本应用写入的条目时系统会拒绝（RecoverableSecurityException 等）
            throw IllegalStateException("该图片不是本应用写入的，系统不允许在应用内删除", e)
        }
    }

    private fun deleteAllImages(): Int {
        var count = 0
        for (row in listImages()) {
            val uri = row["uri"] as? String ?: continue
            try {
                count += contentResolver.delete(Uri.parse(uri), null, null)
            } catch (e: SecurityException) {
                throw IllegalStateException("该图片不是本应用写入的，系统不允许在应用内删除", e)
            }
        }
        return count
    }

    // ===== 分享（通用 ACTION_SEND，不 setPackage）=====

    private fun shareImage(uriStr: String, mime: String): String {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, Uri.parse(uriStr))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // 没有任何应用能接收就早退，给 Dart 侧明确的 unavailable（而非空面板）。
        if (packageManager.queryIntentActivities(send, 0).isEmpty()) {
            return "unavailable"
        }
        val chooser = Intent.createChooser(send, "分享 / 发送图片").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(chooser)
        return "shared"
    }

    /**
     * 查询 GPU 最大纹理边长（GL_MAX_TEXTURE_SIZE）。
     *
     * 用 EGL pbuffer 建一个 1×1 的离屏上下文取真值——引擎把离屏画面交给 GPU 时
     * 任一边超过该值会**静默等比缩小**，Dart 侧超采样档位必须先按它收紧。任何
     * 一步失败都返回 null（不是 0），由 Dart 侧回落常数兜底。
     *
     * 注意：默认 display 与 Flutter 引擎共享，**不调 eglTerminate**（会作废引擎
     * 自己的上下文），只销毁本次自建的 surface / context。
     */
    private fun queryMaxTextureSize(): Int? {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) return null
        val version = IntArray(2)
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) return null

        val configAttribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, numConfigs, 0) ||
            numConfigs[0] == 0
        ) {
            return null
        }
        val surface = EGL14.eglCreatePbufferSurface(
            display,
            configs[0],
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0,
        )
        if (surface == EGL14.EGL_NO_SURFACE) return null
        val context = EGL14.eglCreateContext(
            display,
            configs[0],
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        if (context == EGL14.EGL_NO_CONTEXT) {
            EGL14.eglDestroySurface(display, surface)
            return null
        }

        val size: Int? = try {
            if (!EGL14.eglMakeCurrent(display, surface, surface, context)) {
                null
            } else {
                val value = IntArray(1)
                GLES20.glGetIntegerv(GLES20.GL_MAX_TEXTURE_SIZE, value, 0)
                if (value[0] > 0) value[0] else null
            }
        } finally {
            // 解绑后只清理本次自建资源，display 保留（引擎还在用）。
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroyContext(display, context)
            EGL14.eglDestroySurface(display, surface)
        }
        return size
    }

    /** 后台线程执行耗时 IO，完成后切回主线程返回结果。 */
    private fun <T> runAsync(
        result: MethodChannel.Result,
        errorCode: String,
        job: () -> T,
    ) {
        Thread {
            try {
                val r = job()
                runOnUiThread { result.success(r) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(errorCode, e.message ?: "操作失败", null)
                }
            }
        }.start()
    }
}
