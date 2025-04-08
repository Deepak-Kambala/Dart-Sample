import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';

void main() async {
  final env = DotEnv()..load();

  final apiKey = env['GEMINI_API_KEY'];
  if (apiKey == null) {
    print("API key not found in .env file.");
    return;
  }

  final file = File('lib/untested_code.dart');
  if (!file.existsSync()) {
    print("Source file not found.");
    return;
  }

  final code = await file.readAsString();

  print("📤 Sending code to Gemini...");

  try {
    final response =
        await sendToGemini(code, apiKey).timeout(const Duration(seconds: 30));

    if (response == null) {
      print("No response from Gemini API.");
      return;
    }

    if (response['status'] == 'error') {
      print("Issues found in the code:");
      for (var issue in response['issues'] ?? []) {
        print("- $issue");
      }
    } else if (response['status'] == 'success') {
      print("✅ Code is testable. Gemini generated tests!");
      final tests = response['generated_tests'] ?? '';
      final testFile = File(Platform.isWindows
          ? r'test\generated_tests\test_generated.txt'
          : 'test/generated_tests/test_generated.txt');
      await testFile.create(recursive: true);
      await testFile.writeAsString(tests);
      print("🧪 Tests saved to ${testFile.path}");
    }
  } catch (e) {
    print("Error: $e");
  }
}

Future<Map<String, dynamic>?> sendToGemini(String code, String apiKey) async {
  final prompt = """
You are an AI assistant helping with Dart code testing. 
Analyze the following Dart code. 
1. If it contains issues, return them as a JSON object with 'status'='error' and 'issues' array.
2. If it's valid, generate a test file using the 'test' package and return JSON with 'status'='success' and 'generated_tests' string.

Code:
${code}
""";

  // Updated URL with correct model name
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=${apiKey}',
  );

  final payload = {
    "contents": [
      {
        "parts": [
          {"text": prompt}
        ]
      }
    ]
  };

  try {
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final candidates = body['candidates'];
      if (candidates == null || candidates.isEmpty) {
        print("⚠️ No candidates in response");
        return null;
      }

      final generatedText = candidates[0]['content']['parts'][0]['text'];
      print("Raw response: $generatedText");

      try {
        return jsonDecode(generatedText);
      } catch (e) {
        print("⚠️ Could not parse JSON from Gemini response. Error: $e");
        return {'status': 'success', 'generated_tests': generatedText};
      }
    } else {
      print("❌ Gemini API Error: ${response.statusCode}");
      print("Message: ${response.body}");
      return null;
    }
  } catch (e) {
    print("❌ Network error: $e");
    return null;
  }
}
