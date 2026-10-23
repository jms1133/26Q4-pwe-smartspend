import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openapi/api.dart';

void main() {
  // Erzeugt ein Objekt vom Typ ApiClient mit der URL des lokalen Servers
  final apiClient = ApiClient(basePath: 'http://localhost:8081');

  runApp(
    // Erweitert den Widget-Baum um ein Provider-Widget
    Provider<ApiClient>.value(
      value: apiClient,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ChatGPT Web App')),
        body: const ChatScreen(),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String _aiResponse = "Die Antwort von ChatGPT wird hier angezeigt.";

  Future<void> _askAI() async {
    final apiClient = Provider.of<ApiClient>(context, listen: false);
    final apiInstance = DefaultApi(apiClient);

    // Erzeugt ein Message-Objekt
    final message = Message(
      timestamp: DateTime.now(),
      message: _controller.text,
      author: MessageAuthorEnum.user, 
    );

    setState(() {
      _aiResponse = "Warte auf Antwort vom Server...";
    });

    try {
      // Ruft die REST-Operation über den ApiClient auf
      final result = await apiInstance.chat(message);
      
      setState(() {
        // Zeigt die Antwort des Servers in der UI an
        _aiResponse = result?.message ?? "Keine Nachricht empfangen.";
      });
    } catch (e) {
      setState(() {
        _aiResponse = "Fehler bei der Anfrage: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Ihre Frage eingeben',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _askAI,
            child: const Text('Anfrage senden'),
          ),
          const SizedBox(height: 20),
          Text(_aiResponse),
        ],
      ),
    );
  }
}