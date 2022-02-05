/// Some parts of this file come from the unpub_auth project and are subject
/// to MIT license.
import 'dart:async';
import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../onepub_settings.dart';
import '../util/send_command.dart';

int _port = 42666;

/// Return the auth token or null if the auth failed.
Future<Map<String, Object?>?> bbAuth() async {
  final callbackUrl = 'http://localhost:$_port';

  final onepubUrl = OnepubSettings.load().onepubWebUrl;
  final authUrl = OnepubSettings()
      .resolveWebEndPoint('clilogin', queryParams: 'callback=$callbackUrl');

  final encodedUrl = Uri.encodeFull(authUrl);

  print('''
To login to Onepub.
From a web browser, go to 

${blue(encodedUrl)}

When prompted Sign in.

Waiting for your authorisation...''');

  return _waitForResponse(onepubUrl);
}

/// Returns a map with the response
Future<Map<String, Object?>?> _waitForResponse(
  String onepubWebUrl,

  // oauth2.AuthorizationCodeGrant grant
) async {
  final completer = Completer<Map<String, Object?>?>();
  final server = await bindServer(_port);
  shelf_io.serveRequests(server, (request) async {
    await server.close();
    if (request.url.queryParameters.keys.contains('app_id') &&
        request.url.queryParameters.keys.contains('authentication_token')) {
      print('Authorisation received, processing...');

      final appId = request.url.queryParameters['app_id']!;
      final token = request.url.queryParameters['authentication_token']!;

      // Forward the oauth details to the server so it can validate us.
      final response = await sendCommand(
          command: 'oauthFinalise'
              '?app_id=$appId&authentication_token=$token',
          authorised: false);

      if (!response.success) {
        completer.complete(null);
        return shelf.Response.notFound('Invalid Request.');
      }

      /// Redirect to authorised page.
      completer.complete(response.data);
      return shelf.Response.found('$onepubWebUrl/cliauthorised');

      //return shelf.Response.ok('Onepub successfully authorised.');
    } else {
      completer.complete(null);

      /// Forbid all other requests.
      return shelf.Response.notFound('Invalid Request.');
    }
  });

  return completer.future;
}

/// Bind local server to handle oauth redirect
Future<HttpServer> bindServer(int port) async {
  final server = await HttpMultiServer.loopback(port);
  server.autoCompress = true;
  return server;
}

Map<String, String> queryToMap(String queryList) {
  final map = <String, String>{};
  for (final pair in queryList.split('&')) {
    final split = _split(pair, '=');
    if (split.isEmpty) {
      continue;
    }
    final key = _urlDecode(split[0]);
    final value = split.length > 1 ? _urlDecode(split[1]) : '';
    map[key] = value;
  }
  return map;
}

List<String> _split(String toSplit, String pattern) {
  if (toSplit.isEmpty) {
    return <String>[];
  }

  final index = toSplit.indexOf(pattern);
  if (index == -1) {
    return [toSplit];
  }
  return [
    toSplit.substring(0, index),
    toSplit.substring(index + pattern.length)
  ];
}

String _urlDecode(String encoded) =>
    Uri.decodeComponent(encoded.replaceAll('+', ' '));
