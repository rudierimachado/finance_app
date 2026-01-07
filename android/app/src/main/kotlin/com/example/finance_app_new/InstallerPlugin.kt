package com.example.finance_app_new

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import java.io.File

object InstallerPlugin {
    fun installApk(@NonNull context: Context, apkPath: String) {
        val file = File(apkPath)
        if (!file.exists()) {
            throw IllegalArgumentException("APK não encontrado no caminho: $apkPath")
        }

        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
            } catch (e: Exception) {
                throw IllegalStateException("Erro ao obter URI do FileProvider: ${e.message}. Verifique o authorities no AndroidManifest.")
            }
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            // Adicionar categoria padrão
            addCategory(Intent.CATEGORY_DEFAULT)
        }

        // Para Android 11+ (API 30), opcionalmente podemos usar ACTION_INSTALL_PACKAGE
        // mas ACTION_VIEW com o MIME type correto ainda é amplamente suportado.

        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            throw RuntimeException("Falha ao iniciar atividade de instalação: ${e.message}")
        }
    }
}
