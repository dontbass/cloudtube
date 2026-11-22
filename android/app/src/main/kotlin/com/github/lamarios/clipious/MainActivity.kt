package com.github.lamarios.clipious

import android.content.Intent
import android.content.res.Configuration
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import cl.puntito.simple_pip_mode.PipCallbackHelper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : AudioServiceActivity() {
    private var callbackHelper = PipCallbackHelper()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callbackHelper.configureFlutterEngine(flutterEngine)

        // CloudTube: обновление приложения из самого приложения
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cloudtube/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        result.success(true)
                    }
                    "install" -> {
                        val file = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.ctupdate", file)
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message, null)
            }
        }

        // CloudTube: склейка скачанных видео и звука (без перекодирования)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cloudtube/media").setMethodCallHandler { call, result ->
            if (call.method != "mux") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val video = call.argument<String>("video")!!
            val audio = call.argument<String>("audio")!!
            val out = call.argument<String>("out")!!
            Thread {
                try {
                    mux(video, audio, out)
                    runOnUiThread { result.success(true) }
                } catch (e: Exception) {
                    File(out).delete()
                    runOnUiThread { result.error("mux", e.message ?: e.toString(), null) }
                }
            }.start()
        }
    }

    private fun mux(videoPath: String, audioPath: String, outPath: String) {
        val sources = listOf(videoPath to "video/", audioPath to "audio/")
        val extractors = ArrayList<MediaExtractor>()
        var muxer: MediaMuxer? = null
        try {
            val formats = ArrayList<MediaFormat>()
            for ((path, want) in sources) {
                val ex = MediaExtractor()
                extractors.add(ex)
                ex.setDataSource(path)
                var found = false
                for (t in 0 until ex.trackCount) {
                    val f = ex.getTrackFormat(t)
                    if (f.getString(MediaFormat.KEY_MIME)?.startsWith(want) == true) {
                        ex.selectTrack(t)
                        formats.add(f)
                        found = true
                        break
                    }
                }
                if (!found) throw IllegalStateException("no $want track in $path")
            }
            // VP8/VP9 + Opus/Vorbis — контейнер WebM, остальное (H.264 + AAC) — MP4
            val vMime = formats[0].getString(MediaFormat.KEY_MIME) ?: ""
            val webm = vMime.contains("vp8") || vMime.contains("vp9") || vMime.contains("vnd.on2")
            val m = MediaMuxer(
                outPath,
                if (webm) MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM else MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
            )
            muxer = m
            val tracks = formats.map { m.addTrack(it) }
            m.start()
            val buffer = ByteBuffer.allocate(8 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                // по очереди: дорожка с меньшей меткой времени — так требует контейнер
                var pick = -1
                var best = Long.MAX_VALUE
                for (i in extractors.indices) {
                    val ts = extractors[i].sampleTime
                    if (ts >= 0 && ts < best) {
                        best = ts
                        pick = i
                    }
                }
                if (pick < 0) break
                val ex = extractors[pick]
                buffer.clear()
                val size = ex.readSampleData(buffer, 0)
                if (size < 0) break
                info.set(
                    0, size, ex.sampleTime,
                    if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                )
                m.writeSampleData(tracks[pick], buffer, info)
                ex.advance()
            }
            m.stop()
        } finally {
            try { muxer?.release() } catch (_: Exception) {}
            for (ex in extractors) ex.release()
        }
    }

    override fun onPictureInPictureModeChanged(active: Boolean, newConfig: Configuration?) {
        callbackHelper.onPictureInPictureModeChanged(active)
    }
}
