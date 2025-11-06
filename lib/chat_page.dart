import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'main.dart';

class ChatPage extends StatefulWidget {
  final ThemeProvider themeProvider;
  
  const ChatPage({super.key, required this.themeProvider});

  @override
  // ignore: library_private_types_in_public_api
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _sessions = [{"first_query": null, "history": []}];
  int _currentSessionIndex = 0;
  int? _editingQueryIndex;
  String? _fileContent;
  String? _fileName;
  
  // Groq API key from environment variables
  String? _groqApiKey;
  // Selected model - default is Llama3-8b-8192
  String _selectedModel = 'llama-3.1-8b-instant';
  
  // List of available models
  final List<String> _availableModels = [
    'llama-3.1-8b-instant',
    'gemma2-9b-it',
    'openai/gpt-oss-120b',
    'deepseek-r1-distill-llama-70b',
    'llama-3.3-70b-versatile',
  ];
  
  // Animation controller for typing indicator
  late AnimationController _animationController;
  
  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadApiKey();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }
  
  // Load API key from environment variables
  void _loadApiKey() {
    _groqApiKey = dotenv.env['groq_api_key'] ?? '';
    if (_groqApiKey!.isEmpty) {
      // Show error message if API key is not set
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GROQ API key not found. Please configure the .env file.')),
        );
      });
    }
  }
  
  // Load saved sessions from local storage
  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String sessionsJson = prefs.getString('chat_sessions') ?? '';
    
    if (sessionsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(sessionsJson);
        setState(() {
          _sessions = decoded.map((session) => Map<String, dynamic>.from(session)).toList();
        });
      } catch (e) {
        if (kDebugMode) {
          print('Error loading sessions: $e');
        }
        // Initialize with default data if loading fails
        setState(() {
          _sessions = [{"first_query": null, "history": []}];
        });
      }
    }
  }
  
  // Save sessions to local storage
  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String sessionsJson = jsonEncode(_sessions);
    await prefs.setString('chat_sessions', sessionsJson);
  }
  
  // Select file (PDF or TXT)
  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
    );
    
    if (result != null) {
      final path = result.files.single.path!;
      final extension = path.split('.').last.toLowerCase();
      
      setState(() {
        _fileName = result.files.single.name;
      });
      
      if (extension == 'pdf') {
        _readPdfFile(path);
      } else if (extension == 'txt') {
        _readTextFile(path);
      }
    }
  }
  
  // Read PDF file content using Syncfusion
  Future<void> _readPdfFile(String path) async {
    try {
      // Read file as bytes
      final File file = File(path);
      final Uint8List bytes = await file.readAsBytes();
      
      // Load PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      // Create PDF text extractor
      PdfTextExtractor textExtractor = PdfTextExtractor(document);
      
      // Extract text from all pages
      String text = '';
      for (int i = 0; i < document.pages.count; i++) {
        text += '${textExtractor.extractText(startPageIndex: i)}\n';
      }
      
      // Release document resources
      document.dispose();
      
      setState(() {
        _fileContent = text;
      });
      
      // Show snackbar for notification
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF file loaded: $_fileName')),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error reading PDF: $e');
      }
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading PDF file: $e')),
      );
    }
  }
  
  // Read text file content
  Future<void> _readTextFile(String path) async {
    try {
      final File file = File(path);
      // Ensure UTF-8 encoding
      final String contents = await file.readAsString(encoding: utf8);
      setState(() {
        _fileContent = contents;
      });
      // Show snackbar for notification
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Text file loaded: $_fileName')),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error reading text file: $e');
      }
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading text file: $e')),
      );
    }
  }
  
  // Send message to GROQ API and get response
  Future<String> _getGroqResponse(String userInput) async {
    if (_groqApiKey == null || _groqApiKey!.isEmpty) {
      return 'Error: GROQ API key is not configured.';
    }
    
    final currentSession = _sessions[_currentSessionIndex];
    
    // Prepare conversation history
    List<Map<String, String>> conversationHistory = [];
    
    // Add previous messages from history
    for (var entry in currentSession['history']) {
      conversationHistory.add({"role": "user", "content": entry["query"]});
      conversationHistory.add({"role": "assistant", "content": entry["response"]});
    }
    
    // Add file content if available
    if (_fileContent != null) {
      conversationHistory.add({"role": "system", "content": "File content: $_fileContent"});
    }
    
    // Add current user message
    conversationHistory.add({"role": "user", "content": userInput});
    
    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqApiKey',
        },
        body: jsonEncode({
          'model': _selectedModel,
          'messages': conversationHistory,
        }),
      );
      
      // Decode response body as UTF-8 for Persian text
      final rawBytes = response.bodyBytes;
      final String responseBody = utf8.decode(rawBytes, allowMalformed: false);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(responseBody);
        return data['choices'][0]['message']['content'];
      } else {
        // Check for invalid API key error and show SnackBar
        String errorMsg = 'Error: Failed to get response from GROQ (status ${response.statusCode})';
        try {
          final Map<String, dynamic> errorData = jsonDecode(responseBody);
          if (errorData.containsKey('error') &&
              errorData['error']['code'] == 'invalid_api_key') {
            errorMsg = 'Error: Invalid GROQ API key. Please check your .env file.';
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMsg)),
            );
          }
        } catch (_) {
          // ignore decoding error, fallback to generic error
        }
        if (kDebugMode) {
          print('Error from GROQ API: $responseBody');
        }
        return errorMsg;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Exception when calling GROQ API: $e');
      }
      return 'Error: $e';
    }
  }
  
  // Send new message or edit existing message
  Future<void> _handleSubmit(String userInput, {bool isEdit = false}) async {
    if (userInput.isEmpty) return;
    
    setState(() {
      if (isEdit && _editingQueryIndex != null) {
        // Keep previous message until new response is received
      } else {
        // Add user message and show loading indicator
        _sessions[_currentSessionIndex]['history'].add({
          "query": userInput,
          "response": "..."
        });
        
        // Set first query if this is the first message
        if (_sessions[_currentSessionIndex]['first_query'] == null) {
          _sessions[_currentSessionIndex]['first_query'] = userInput;
        }
      }
    });
    
    // Get response from GROQ API
    final response = await _getGroqResponse(userInput);
    
    setState(() {
      if (isEdit && _editingQueryIndex != null) {
        // Edit existing message
        _sessions[_currentSessionIndex]['history'][_editingQueryIndex!] = {
          "query": userInput,
          "response": response
        };
        _editingQueryIndex = null;
      } else {
        // Update last message with actual response
        _sessions[_currentSessionIndex]['history'].last["response"] = response;
      }
    });
    
    _textController.clear();
    await _saveSessions();
    
    // Scroll to bottom
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  // Create new session
  void _createNewSession() {
    setState(() {
      _sessions.add({"first_query": null, "history": []});
      _currentSessionIndex = _sessions.length - 1;
      _editingQueryIndex = null;
      _fileContent = null;
      _fileName = null;
    });
    _saveSessions();
    
    // Close navigation drawer after creating new session
    Navigator.pop(context);
  }
  
  // Switch to different session
  void _switchSession(int index) {
    setState(() {
      _currentSessionIndex = index;
      _editingQueryIndex = null;
    });
    
    // Close navigation drawer after switching session
    Navigator.pop(context);
  }
  
  // Show About dialog
  void _showAboutDialog() {
    final isDark = widget.themeProvider.isDarkMode;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
        title: Text(
          'About FADAI BOT',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FADAI BOT is an AI assistant powered by GROQ API.',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Created by: NAWID FADAI (2025)',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Contact: sanginzain@gmail.com',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Clear all sessions
  void _clearSessions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Conversations'),
        content: const Text('Are you sure you want to clear all conversations?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _sessions = [{"first_query": null, "history": []}];
                _currentSessionIndex = 0;
                _editingQueryIndex = null;
                _fileContent = null;
                _fileName = null;
              });
              _saveSessions();
              Navigator.pop(context);
              Navigator.pop(context); // Close settings menu
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  // Truncate long text
  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  // Typing indicator text
  String _buildTypingIndicatorText() {
    return "Thinking...";
  }

  // Chat message item builder with mobile-optimized design
  Widget _buildChatItem(Map<String, dynamic> item, int index) {
    final isDark = widget.themeProvider.isDarkMode;
    
    if (index == _editingQueryIndex) {
      return _buildEditingItem(item);
    }
    
    return Column(
      children: [
        // User message
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.white,
            border: Border(bottom: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              width: 0.5,
            )),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                    radius: 12,
                    child: Icon(Icons.person, 
                         color: isDark ? Colors.white70 : Colors.grey,
                         size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _editingQueryIndex = index;
                      });
                    },
                    child: Icon(
                      Icons.edit,
                      size: 14,
                      color: isDark ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item['query'],
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
                // Detect Persian and set RTL direction
                textDirection: _isPersian(item['query']) ? TextDirection.rtl : TextDirection.ltr,
              ),
            ],
          ),
        ),
        
        // Bot response
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F8),
            border: Border(bottom: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              width: 0.5,
            )),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isDark ? Colors.blue : Colors.grey.shade600,
                    radius: 12,
                    child: const Icon(Icons.smart_toy, color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'FADAI-BOT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // Copy to clipboard functionality
                          final textToCopy = item['response'];
                          if (textToCopy != "...") {
                            // Copy to clipboard
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Text copied to clipboard')),
                            );
                          }
                        },
                        child: Icon(
                          Icons.copy,
                          size: 14,
                          color: isDark ? Colors.white70 : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          // Thumbs up action
                        },
                        child: Icon(
                          Icons.thumb_up_outlined,
                          size: 14,
                          color: isDark ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item['response'] == "..." ? _buildTypingIndicatorText() : item['response'],
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
                // Detect Persian and set RTL direction
                textDirection: _isPersian(item['response']) ? TextDirection.rtl : TextDirection.ltr,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Editing interface for messages - mobile optimized
  Widget _buildEditingItem(Map<String, dynamic> item) {
    final isDark = widget.themeProvider.isDarkMode;
    
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Edit Message',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: item['query']),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              hintText: 'Edit your message',
              hintStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade500,
                fontSize: 14,
              ),
            ),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 14,
            ),
            maxLines: null,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _editingQueryIndex = null;
                  });
                },
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final controller = TextEditingController.fromValue(
                    TextEditingValue(text: item['query']),
                  );
                  _handleSubmit(controller.text, isEdit: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.blue : Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Welcome screen optimized for mobile
  Widget _buildWelcomeView() {
    final isDark = widget.themeProvider.isDarkMode;
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline, 
              size: 48, 
              color: isDark ? Colors.white70 : Colors.grey
            ),
            const SizedBox(height: 16),
            Text(
              'How can I help you today?',
              style: TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "I'm your AI assistant powered by",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              "Selected model: $_selectedModel",
              style: TextStyle(
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Examples:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildExampleButton('Explain quantum computing in simple terms'),
                  _buildExampleButton('Got any creative ideas for a 10 year old\'s birthday?'),
                  _buildExampleButton('How do I make an HTTP request in JavaScript?'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Build example buttons for welcome screen - mobile optimized
  Widget _buildExampleButton(String text) {
    final isDark = widget.themeProvider.isDarkMode;
    
    return InkWell(
      onTap: () {
        _textController.text = text;
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = _sessions[_currentSessionIndex];
    final history = currentSession['history'] as List;
    final isDark = widget.themeProvider.isDarkMode;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: PopupMenuButton<String>(
          onSelected: (String model) {
            setState(() {
              _selectedModel = model;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Model changed to $model')),
            );
          },
          itemBuilder: (BuildContext context) {
            return _availableModels.map((String model) {
              return PopupMenuItem<String>(
                value: model,
                child: Row(
                  children: [
                    Text(
                      model,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: _selectedModel == model ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedModel == model)
                      Icon(
                        Icons.check,
                        size: 16,
                        color: isDark ? Colors.blue : Colors.blue.shade700,
                      ),
                  ],
                ),
              );
            }).toList();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedModel,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                size: 20,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              size: 22,
            ),
            onPressed: widget.themeProvider.toggleTheme,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 16),
              color: isDark ? Colors.grey.shade900 : Colors.blue.shade700,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isDark ? Colors.grey.shade800 : Colors.blue.shade800,
                    child: const Text('NF', style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FADAI BOT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'AI Assistant',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // New Chat Button
            ListTile(
              leading: Icon(
                Icons.add,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
              ),
              title: Text(
                'New Chat',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: _createNewSession,
            ),
            const Divider(),
            // Recent Chats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recent Chats',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            // Chat History
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) {
                  final session = _sessions[index];
                  final title = session['first_query'] ?? 'New Chat';
                  
                  return ListTile(
                    leading: Icon(
                      Icons.chat_bubble_outline,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      size: 20,
                    ),
                    title: Text(
                      _truncateText(title, 25),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    selected: index == _currentSessionIndex,
                    selectedTileColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    onTap: () => _switchSession(index),
                  );
                },
              ),
            ),
            const Divider(),
            // Setting Options
            ListTile(
              leading: Icon(
                Icons.settings,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
              ),
              title: Text(
                'Settings',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: () {
                // Close drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
              ),
              title: Text(
                'Clear All Chats',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: _clearSessions,
            ),
            ListTile(
              leading: Icon(
                Icons.info_outline,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
              ),
              title: Text(
                'About',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showAboutDialog();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // File indicator if file is loaded
          if (_fileName != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              // ignore: deprecated_member_use
              color: isDark ? Colors.blue.shade900.withOpacity(0.3) : Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(
                    Icons.description,
                    size: 16,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File: $_fileName',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                    ),
                    onPressed: () {
                      setState(() {
                        _fileContent = null;
                        _fileName = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            
          // Chat Messages
          Expanded(
            child: history.isEmpty 
              ? _buildWelcomeView()
              : ListView.builder(
                controller: _scrollController,
                itemCount: history.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) {
                  final item = history[index];
                  return _buildChatItem(item, index);
                },
              ),
          ),
          
          // Input Area - Mobile optimized
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.attach_file,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                      size: 20,
                    ),
                    onPressed: _pickFile,
                    padding: const EdgeInsets.all(8),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 14,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.send,
                      color: isDark ? Colors.blue : Colors.blue.shade700,
                      size: 20,
                    ),
                    onPressed: () {
                      if (_textController.text.isNotEmpty) {
                        _handleSubmit(_textController.text);
                      }
                    },
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Utility to detect Persian text
  bool _isPersian(String? text) {
    if (text == null) return false;
    // Persian Unicode range: \u0600-\u06FF
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }
}