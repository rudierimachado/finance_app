import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'open_url.dart';
import 'config.dart';

class AttachmentsPage extends StatefulWidget {
  final int userId;
  final int transactionId;
  final String transactionDescription;

  const AttachmentsPage({
    super.key,
    required this.userId,
    required this.transactionId,
    required this.transactionDescription,
  });

  @override
  State<AttachmentsPage> createState() => _AttachmentsPageState();
}

class _AttachmentsPageState extends State<AttachmentsPage> {
  List<_Attachment> _attachments = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _openAttachment(_Attachment attachment) async {
    final viewUrl = attachment.viewUrl;
    if (viewUrl == null || viewUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link do comprovante indisponível.')),
        );
      }
      return;
    }

    final ok = await openExternalUrl('$apiBaseUrl$viewUrl');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o comprovante neste dispositivo.')),
      );
    }
  }

  Future<void> _loadAttachments() async {
    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse(
        '$apiBaseUrl/gerenciamento-financeiro/api/transactions/${widget.transactionId}/attachments?user_id=${widget.userId}',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        final attachmentsList = (data['attachments'] as List<dynamic>? ?? []);
        setState(() {
          _attachments = attachmentsList.map((item) {
            final id = item['id'] as int;
            final viewUrl = item['view_url']?.toString() ??
                '/gerenciamento-financeiro/api/transactions/${widget.transactionId}/attachments/$id/file?user_id=${widget.userId}';
            return _Attachment(
              id: id,
              fileName: item['file_name'] as String,
              fileSize: item['file_size'] as int,
              uploadedAt: DateTime.parse(item['uploaded_at'] as String),
              viewUrl: viewUrl,
            );
          }).toList();
          _isLoading = false;
        });
      } else {
        throw Exception(data['message'] ?? 'Erro ao carregar comprovantes');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      
      // Validar tamanho (1MB = 1048576 bytes)
      if (file.size > 1048576) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Arquivo maior que 1MB. Escolha um arquivo menor.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final uri = Uri.parse(
        '$apiBaseUrl/gerenciamento-financeiro/api/transactions/${widget.transactionId}/attachments?user_id=${widget.userId}',
      );

      var request = http.MultipartRequest('POST', uri);
      
      if (kIsWeb) {
        // Web: usar bytes
        if (file.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
            contentType: MediaType('application', 'octet-stream'),
          ));
        }
      } else {
        // Mobile/Desktop: usar path
        if (file.path != null) {
          request.files.add(await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ));
        }
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      setState(() => _isUploading = false);

      if (response.statusCode == 201 && data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comprovante enviado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadAttachments();
      } else {
        throw Exception(data['message'] ?? 'Erro ao enviar arquivo');
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAttachment(int attachmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        title: const Text('Remover comprovante', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tem certeza que deseja remover este comprovante?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/gerenciamento-financeiro/api/transactions/${widget.transactionId}/attachments/$attachmentId?user_id=${widget.userId}',
      );

      final response = await http.delete(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comprovante removido'), backgroundColor: Colors.green),
          );
        }
        await _loadAttachments();
      } else {
        throw Exception(data['message'] ?? 'Erro ao remover');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprovantes'),
        backgroundColor: const Color(0xFF0F2027),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.transactionDescription,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Máximo 1MB por arquivo',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C9A7)))
                    : _attachments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.attach_file, size: 64, color: Colors.white.withOpacity(0.3)),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhum comprovante anexado',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _attachments.length,
                            itemBuilder: (context, index) {
                              final attachment = _attachments[index];
                              return Card(
                                color: Colors.white.withOpacity(0.08),
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.insert_drive_file, color: Color(0xFF00C9A7)),
                                  title: Text(
                                    attachment.fileName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${_formatFileSize(attachment.fileSize)} • ${_formatDate(attachment.uploadedAt)}',
                                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.visibility, color: Colors.white),
                                        tooltip: 'Ver',
                                        onPressed: () => _openAttachment(attachment),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        tooltip: 'Excluir',
                                        onPressed: () => _deleteAttachment(attachment.id),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _pickAndUploadFile,
        backgroundColor: const Color(0xFF00C9A7),
        foregroundColor: Colors.white,
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_isUploading ? 'Enviando...' : 'Adicionar'),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _Attachment {
  final int id;
  final String fileName;
  final int fileSize;
  final DateTime uploadedAt;
  final String? viewUrl;

  _Attachment({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.uploadedAt,
    required this.viewUrl,
  });
}
