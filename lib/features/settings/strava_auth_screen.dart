import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../i18n/app_i18n.dart';

class StravaAuthScreen extends StatefulWidget {
  const StravaAuthScreen({super.key, required this.authUrl});

  final String authUrl;

  @override
  State<StravaAuthScreen> createState() => _StravaAuthScreenState();
}

class _StravaAuthScreenState extends State<StravaAuthScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('stravasync://')) {
              final uri = Uri.parse(request.url);
              final code = uri.queryParameters['code'];
              if (code != null && code.isNotEmpty) {
                Navigator.of(context).pop(code);
              } else {
                Navigator.of(context).pop('');
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Clear cache to allow switching accounts easily
    _controller.clearCache().then((_) {
      _controller.clearLocalStorage().then((_) {
        _controller.loadRequest(Uri.parse(widget.authUrl));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppI18n.s(context).stravaAuthActionConnect),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
