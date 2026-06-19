import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  late WebSocketChannel _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  bool _isConnected = false;
  String? _lastUrl;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<bool> get connectionStatus => _connectionController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect(String url) async {
    _lastUrl = url;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel.stream.listen(
        _handleMessage,
        onError: (_) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );
      _isConnected = true;
      _connectionController.add(true);
      print('Connected to WebSocket');
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      print('WebSocket connection failed: $e');
      scheduleReconnect();
    }
  }

  void _handleDisconnect() {
    if (_isConnected) {
      print('WebSocket disconnected');
    }
    _isConnected = false;
    _connectionController.add(false);
    _channel.sink.close();
    scheduleReconnect();
  }

  void scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    print('Attempting to reconnect in 5 seconds...');
    _reconnectTimer = Timer(Duration(seconds: 5), () {
      if (!_isConnected && _lastUrl != null) {
        connect(_lastUrl!);
      }
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      _messageController.add(data);

      if (data['requestId'] != null &&
          _pendingRequests.containsKey(data['requestId'])) {
        final completer = _pendingRequests.remove(data['requestId']);
        if (data['status'] == 'success') {
          completer?.complete(data);
        } else {
          completer?.completeError(data['error'] ?? 'Request failed');
        }
      }
    } catch (e) {
      _messageController.addError('Message parsing failed: $e');
    }
  }

  Future<Map<String, dynamic>> sendRequest(
    String type,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!_isConnected) throw Exception('Not connected to WebSocket');
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    final request = jsonEncode({
      'type': type,
      'requestId': requestId,
      'payload': payload,
    });

    _channel.sink.add(request);
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRequests.remove(requestId);
      throw TimeoutException('Request timed out');
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel.sink.close();
    _messageController.close();
    _connectionController.close();
  }
}
