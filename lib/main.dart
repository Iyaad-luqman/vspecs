import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:hardware_button_listener/hardware_button_listener.dart';
import 'package:hardware_button_listener/models/hardware_button.dart';

void main() => runApp(VisionAIApp());

class VisionAIApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VisionAI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AudioScreen(),
    );
  }
}

class AudioScreen extends StatefulWidget {
  @override
  _AudioScreenState createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  bool isLoading = false;
  String? responseText;
  String? serverUrl;
  FlutterTts flutterTts = FlutterTts();
  FlutterSoundRecorder? _recorder;
  bool isRecording = false;
  String? audioPath;
  String selectedMode = 'Face'; // Default mode
  final _hardwareButtonListener = HardwareButtonListener();
  late StreamSubscription<HardwareButton> _buttonSubscription;

  @override
  void initState() {
    super.initState();
    fetchServerUrl();
    requestPermissions();
    _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
    startListeningToHardwareButtons();
  }

  Future<void> requestPermissions() async {
    await Permission.microphone.request();
  }

  Future<void> fetchServerUrl() async {
    try {
      final response = await http.get(Uri.parse('https://api.jsonbin.io/v3/b/66f3e256acd3cb34a88b43d2'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          serverUrl = data['record']['url'];
        });
      } else {
        print('Failed to fetch server URL');
      }
    } catch (e) {
      print('Error fetching server URL: $e');
    }
  }

  void startListeningToHardwareButtons() {
    _buttonSubscription = _hardwareButtonListener.listen((event) {
    debugPrint(event.buttonKey.toString());
      if (event.buttonKey == 24) {
        startRecording();
      } else if (event.buttonKey == 25) {
        stopRecordingAndSend();
      }
    });
  }

  Future<void> startRecording() async {
    if (!isRecording) {
      await _recorder!.startRecorder(toFile: 'audio.aac');
      setState(() {
        isRecording = true;
      });
    }
  }

  Future<void> stopRecordingAndSend() async {
    if (isRecording) {
      audioPath = await _recorder!.stopRecorder();
      setState(() {
        isRecording = false;
      });
      sendAudio();
    }
  }

  Future<void> sendAudio() async {
    if (serverUrl == null) {
      await fetchServerUrl();
      if (serverUrl == null) {
        print('Failed to fetch server URL');
        return;
      }
    }
    setState(() {
      isLoading = true;
    });

    try {
      final audioBytes = await File(audioPath!).readAsBytes();

      final response = await http.post(
        Uri.parse('$serverUrl/uploads'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'audio': base64Encode(audioBytes),
          'mode': selectedMode, // Include selected mode in the request
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        responseText = responseData['response'];
        await flutterTts.speak(responseText!);
        print('Upload successful');
      } else {
        print('Failed to upload');
      }
    } catch (e) {
      print('Error during upload: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    _recorder!.closeRecorder();
    _buttonSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Center(
          child: Text(
            'VisionAI',
            style: TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Color.fromARGB(181, 2, 58, 141),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 0),
            child: Container(
              decoration: BoxDecoration(
                color: Color.fromARGB(255, 31, 0, 102).withOpacity(0),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'images/bg.png',
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  // Dropdown for selecting mode
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: DropdownButton<String>(
                      value: selectedMode,
                      items: <String>['Face', 'Object', 'Scene']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedMode = newValue!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.all(16.0),
                color: Colors.black,
                width: double.infinity,
                child: Text(
                  responseText ?? '',
                  style: TextStyle(color: Colors.white, fontSize: 18.0),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (isLoading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}