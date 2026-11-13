package com.example.symphonium_clone

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentValues
import android.content.Intent
import android.content.ContentUris
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.util.AtomicFile
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.io.File
import org.json.JSONObject
import org.json.JSONArray

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.example.symphonium_clone/audio_library"
    private val permissionRequestCode = 4281
    private val queryExecutor = Executors.newSingleThreadExecutor()
    private val artworkExecutor = Executors.newFixedThreadPool(2)
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val testPermissionCode = 4284
    private var pendingTestPermission: MethodChannel.Result? = null
    private val renamePermissionCode = 4282
    private val renameIntentCode = 4283
    private var pendingRename: Triple<Uri, String, MethodChannel.Result>? = null
    private var renameConsentAttempted = false

    override fun onResume() {
        super.onResume()
        preferHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) preferHighRefreshRate()
    }

    @Suppress("DEPRECATION")
    private fun preferHighRefreshRate() {
        // Request a supported rate without locking the resolution or a mode ID.
        // Android retains control for power saving, thermal limits and user settings.
        val screen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
            else windowManager.defaultDisplay
        screen ?: return
        val current = screen.mode
        val preferred = screen.supportedModes
            .filter { it.physicalWidth == current.physicalWidth &&
                it.physicalHeight == current.physicalHeight && it.refreshRate <= 144.5f }
            .maxOfOrNull { it.refreshRate } ?: return
        val attributes = window.attributes
        if (attributes.preferredRefreshRate != preferred) {
            attributes.preferredRefreshRate = preferred
            window.attributes = attributes
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BackgroundDownloadBridge.attach(this, flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestSyntheticReadPermission" -> {
                        if (!packageName.endsWith(".integration")) {
                            result.notImplemented()
                        } else if (hasAudioAccess()) {
                            result.success(true)
                        } else if (pendingTestPermission != null) {
                            result.error("busy", "Permission request pending", null)
                        } else {
                            pendingTestPermission = result
                            val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                                Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
                            requestPermissions(arrayOf(permission), testPermissionCode)
                        }
                    }
                    "getAudioFileName" -> {
                        val uri = call.argument<String>("uri")
                        queryExecutor.execute {
                            try {
                                val name = audioFilename(Uri.parse(uri ?: ""))
                                runOnUiThread { result.success(name) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("filename_failed", "Cannot read file name", null) }
                            }
                        }
                    }
                    "renameAudioFile" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        val name = call.argument<String>("name") ?: ""
                        if (pendingRename != null) {
                            result.error("rename_busy", "Rename in progress", null)
                        } else {
                            pendingRename = Triple(uri, name, result)
                            renameConsentAttempted = false
                            beginRename()
                        }
                    }
                    "scanAudio" -> requestAudioAccessAndScan(result)
                    "loadLibrary" -> loadLibrary(result)
                    "loadSavedMusic", "loadPlaybackMemory", "loadServerCache", "loadBackupJournal", "loadRenameTitleJournal" -> {
                        val fileName = if (call.method == "loadRenameTitleJournal") "rename_title_journal.json" else if (call.method == "loadBackupJournal") "backup_restore_journal.json" else if (call.method == "loadServerCache") "server_library.json" else if (call.method == "loadSavedMusic") "saved_music.json" else "playback_memory.json"
                        queryExecutor.execute {
                            try {
                                val file = AtomicFile(File(filesDir, fileName))
                                val saved = try {
                                    file.openRead().bufferedReader().use { it.readText() }
                                } catch (_: java.io.FileNotFoundException) { null }
                                runOnUiThread { result.success(saved) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("saved_music_load_failed", error.localizedMessage, null) }
                            }
                        }
                    }
                    "saveSavedMusic", "savePlaybackMemory", "saveServerCache", "saveBackupJournal", "saveRenameTitleJournal" -> {
                        val fileName = if (call.method == "saveRenameTitleJournal") "rename_title_journal.json" else if (call.method == "saveBackupJournal") "backup_restore_journal.json" else if (call.method == "saveServerCache") "server_library.json" else if (call.method == "saveSavedMusic") "saved_music.json" else "playback_memory.json"
                        val json = call.argument<String>("json")
                        if (json == null) {
                            result.error("invalid_data", "Missing saved music", null)
                        } else queryExecutor.execute {
                            try {
                                check(JSONObject(json).getInt("version") == 1)
                                val file = AtomicFile(File(filesDir, fileName))
                                val output = file.startWrite()
                                try {
                                    output.write(json.toByteArray(Charsets.UTF_8))
                                    file.finishWrite(output)
                                } catch (error: Exception) {
                                    file.failWrite(output)
                                    throw error
                                }
                                runOnUiThread { result.success(null) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("saved_music_save_failed", error.localizedMessage, null) }
                            }
                        }
                    }
                    "loadArtwork" -> {
                        val source = call.argument<String>("uri")
                        artworkExecutor.execute {
                            val bytes = source?.let { loadArtwork(it) }
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    "loadSourceFolders" -> {
                        try {
                            val saved = getSharedPreferences("library_sources", MODE_PRIVATE)
                                .getString("folders", null)
                            val folders = saved?.let {
                                val array = JSONArray(it)
                                (0 until array.length()).map { index -> array.getString(index) }
                            }
                            result.success(folders)
                        } catch (error: Exception) {
                            result.error("sources_load_failed", error.localizedMessage, null)
                        }
                    }
                    "saveSourceFolders" -> {
                        val folders = call.argument<List<String>>("folders")
                        queryExecutor.execute {
                            val editor = getSharedPreferences("library_sources", MODE_PRIVATE).edit()
                            if (folders == null) editor.remove("folders")
                            else editor.putString("folders", JSONArray(folders).toString())
                            val saved = editor.commit()
                            runOnUiThread {
                                if (saved) result.success(null)
                                else result.error("save_failed", "Could not save source folders", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun loadArtwork(source: String): ByteArray? {
        val uri = Uri.parse(source)
        if (!hasAudioAccess() || uri.scheme != "content" || uri.authority != "$packageName.artwork") {
            return null
        }
        return try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun hasAudioAccess(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun libraryFile() = AtomicFile(File(filesDir, "audio_library.json"))

    private fun saveLibrary(tracks: List<Map<String, Any>>) {
        val data = JSONObject()
            .put("version", 3)
            .put("tracks", JSONArray(tracks))
            .toString().toByteArray(Charsets.UTF_8)
        val file = libraryFile()
        val output = file.startWrite()
        try {
            output.write(data)
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    private fun loadLibrary(result: MethodChannel.Result) {
        queryExecutor.execute {
            try {
                if (!hasAudioAccess()) {
                    runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
                    return@execute
                }
                val cached = try {
                    val data = libraryFile().openRead().bufferedReader().use { it.readText() }
                    val root = JSONObject(data)
                    check(root.getInt("version") == 3)
                    val rows = root.getJSONArray("tracks")
                    (0 until rows.length()).map { index ->
                        val row = rows.getJSONObject(index)
                        mapOf<String, Any>(
                            "id" to row.getString("id"),
                            "title" to row.getString("title"),
                            "artist" to row.getString("artist"),
                            "album" to row.getString("album"),
                            "genre" to row.optString("genre", ""),
                            "year" to row.optInt("year", 0).takeIf { it in 1..9999 }.let { it ?: 0 },
                            "durationMs" to row.getLong("durationMs"),
                            "uri" to row.getString("uri"),
                            "folder" to row.getString("folder"),
                            "modifiedSeconds" to row.getLong("modifiedSeconds"),
                        )
                    }
                } catch (_: Exception) {
                    null
                }
                // Seed the cache on upgrade or recover a missing/damaged cache.
                val tracks = cached ?: readAudioTracks().also { saveLibrary(it) }
                runOnUiThread { result.success(tracks) }
            } catch (error: Exception) {
                runOnUiThread { result.error("load_failed", error.localizedMessage, null) }
            }
        }
    }

    private fun requestAudioAccessAndScan(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("scan_in_progress", "A music scan is already in progress.", null)
            return
        }

        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            scanAudio(result)
        } else {
            pendingPermissionResult = result
            requestPermissions(arrayOf(permission), permissionRequestCode)
        }
    }

    @Deprecated("Deprecated in Android, but required for this permission flow.")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BackgroundDownloadBridge.PERMISSION) {
            BackgroundDownloadBridge.permissionResult(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            return
        }
        if (requestCode == testPermissionCode) {
            pendingTestPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingTestPermission = null
            return
        }
        if (requestCode == renamePermissionCode) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) performRename()
            else finishRename(false, null)
            return
        }
        if (requestCode != permissionRequestCode) return

        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            scanAudio(result)
        } else {
            result.error(
                "permission_denied",
                "Audio permission was not granted.",
                null,
            )
        }
    }

    private fun audioFilename(uri: Uri): String {
        require(hasAudioAccess() && uri.scheme == "content" && uri.authority == "media")
        require(uri.toString().startsWith("content://media/external/audio/media/"))
        contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0) ?: throw IllegalStateException("Missing name")
        }
        throw IllegalStateException("Track unavailable")
    }

    private fun finishRename(success: Boolean, error: String?) {
        val result = pendingRename?.third ?: return
        pendingRename = null
        if (error == null) result.success(success) else result.error("rename_failed", error, null)
    }

    private fun beginRename() {
        val request = pendingRename ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), renamePermissionCode)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                // Verify the URI before opening the system write dialog.
                audioFilename(request.first)
                val action = MediaStore.createWriteRequest(contentResolver, listOf(request.first))
                startIntentSenderForResult(action.intentSender, renameIntentCode, null, 0, 0, 0)
            } catch (error: Exception) {
                finishRename(false, "Cannot request write access")
            }
        } else performRename()
    }

    @Deprecated("Activity result required by Flutter's activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == renameIntentCode) {
            if (resultCode == Activity.RESULT_OK) performRename() else finishRename(false, null)
        }
    }

    private fun updateRenamedCache(uri: Uri) {
        val root = try {
            JSONObject(libraryFile().openRead().bufferedReader().use { it.readText() })
        } catch (_: java.io.FileNotFoundException) { return }
        val rows = root.getJSONArray("tracks")
        val title = contentResolver.query(uri, arrayOf(MediaStore.Audio.Media.TITLE), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index)
            if (row.optString("uri") == uri.toString()) {
                if (!title.isNullOrEmpty()) row.put("title", title)
                break
            }
        }
        val output = libraryFile().startWrite()
        try {
            output.write(root.toString().toByteArray(Charsets.UTF_8))
            libraryFile().finishWrite(output)
        } catch (error: Exception) {
            libraryFile().failWrite(output)
            throw error
        }
    }

    private fun performRename() {
        val request = pendingRename ?: return
        queryExecutor.execute {
            try {
                val (uri, stem, _) = request
                val current = audioFilename(uri)
                val dot = current.lastIndexOf('.')
                require(dot > 0 && stem.isNotBlank() && stem.length <= 240 &&
                    !stem.endsWith(".") && !stem.endsWith(" ") &&
                    !stem.any { it.code < 32 || it in "\\/<>:\"|?*" })
                val newName = stem + current.substring(dot)
                require(!newName.equals(current, ignoreCase = true))
                val folderColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
                val folder = contentResolver.query(uri, arrayOf(folderColumn), null, null, null)?.use {
                    if (!it.moveToFirst()) throw IllegalStateException("Track unavailable")
                    val value = it.getString(0).orEmpty()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) value else File(value).parent.orEmpty()
                } ?: throw IllegalStateException("Track unavailable")
                val candidateSelection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ? COLLATE NOCASE AND $folderColumn = ? COLLATE NOCASE"
                else "$folderColumn = ? COLLATE NOCASE"
                val candidateArgs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    arrayOf(newName, folder) else arrayOf(File(folder, newName).path)
                contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Audio.Media._ID), candidateSelection, candidateArgs, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        if (cursor.getLong(0).toString() != uri.lastPathSegment)
                            throw IllegalStateException("File already exists")
                    }
                } ?: throw IllegalStateException("Cannot check collisions")
                val updated = contentResolver.update(uri,
                    ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, newName) }, null, null)
                check(updated == 1)
                // The URI remains stable; update only this cached row.
                try { updateRenamedCache(uri) } catch (_: Exception) { /* The rename already succeeded. */ }
                runOnUiThread { finishRename(true, null) }
            } catch (error: SecurityException) {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && error is RecoverableSecurityException && !renameConsentAttempted) {
                    renameConsentAttempted = true
                    runOnUiThread {
                        try { startIntentSenderForResult(error.userAction.actionIntent.intentSender, renameIntentCode, null, 0, 0, 0) }
                        catch (_: Exception) { finishRename(false, "Cannot request write access") }
                    }
                } else runOnUiThread { finishRename(false, "Access denied") }
            } catch (error: Exception) {
                runOnUiThread { finishRename(false, "Could not rename file") }
            }
        }
    }

    private fun scanAudio(result: MethodChannel.Result) {
        queryExecutor.execute {
            try {
                val tracks = readAudioTracks()
                saveLibrary(tracks)
                runOnUiThread { result.success(tracks) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("scan_failed", error.localizedMessage, null)
                }
            }
        }
    }

    private fun readAudioTracks(): List<Map<String, Any>> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.AudioColumns.YEAR,
            MediaStore.Audio.Media.DURATION,
            MediaStore.MediaColumns.DATE_MODIFIED,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA,
        ).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) add(MediaStore.Audio.AudioColumns.GENRE)
        }.toTypedArray()
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        val tracks = mutableListOf<Map<String, Any>>()

        contentResolver.query(collection, projection, selection, null, sortOrder)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val yearColumn = cursor.getColumnIndex(MediaStore.Audio.AudioColumns.YEAR)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val folderColumn = cursor.getColumnIndexOrThrow(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
            )
            val genreColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) cursor.getColumnIndex(MediaStore.Audio.AudioColumns.GENRE) else -1

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val title = cursor.getString(titleColumn).orEmpty()
                if (title.isBlank()) continue

                val artist = cursor.getString(artistColumn)
                    .orEmpty()
                    .takeUnless { it == "<unknown>" }
                    .orEmpty()
                val album = cursor.getString(albumColumn)
                    .orEmpty()
                    .takeUnless { it == "<unknown>" }
                    .orEmpty()
                val duration = cursor.getLong(durationColumn)
                val contentUri = ContentUris.withAppendedId(collection, id).toString()
                val path = cursor.getString(folderColumn).orEmpty()
                val folder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    path.trimEnd('/')
                } else {
                    File(path).parent.orEmpty()
                }

                tracks += mapOf(
                    "id" to id.toString(),
                    "title" to title,
                    "artist" to artist,
                    "album" to album,
                    "genre" to if (genreColumn >= 0) cursor.getString(genreColumn).orEmpty() else "",
                    "year" to if (yearColumn >= 0) cursor.getInt(yearColumn).takeIf { it in 1..9999 }.let { it ?: 0 } else 0,
                    "durationMs" to duration,
                    "uri" to contentUri,
                    "folder" to folder,
                    "modifiedSeconds" to cursor.getLong(modifiedColumn),
                )
            }
        }

        return tracks
    }

    override fun onDestroy() {
        queryExecutor.shutdown()
        artworkExecutor.shutdown()
        super.onDestroy()
    }
}
