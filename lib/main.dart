import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';

void main() => runApp(VisionAIApp());

class VisionAIApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VisionAI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool isCameraInitialized = false;
  bool isLoading = false;
  bool isCaptureInProgress = false;
  String? imageUrl;
  String? responseText;
  String? serverUrl;
  FlutterTts flutterTts = FlutterTts();
  FlutterSoundRecorder? _recorder;
  bool isRecording = false;
  String? audioPath;

  @override
void initState() {
  super.initState();
  fetchServerUrl();
  initializeCamera();
  requestPermissions();
  _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
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

Future<void> initializeCamera() async {
  final cameras = await availableCameras();
  final camera = cameras.first;
  controller = CameraController(camera, ResolutionPreset.high);
  await controller!.initialize();
  setState(() {
    isCameraInitialized = true;
  });
}

Future<void> captureImageAndAudio() async {
  if (controller == null || !controller!.value.isInitialized) {
    print('Controller is not initialized');
    return;
  }
  if (isCaptureInProgress) {
    print('Capture already in progress');
    return;
  }
  if (serverUrl == null) {
    await fetchServerUrl();
    if (serverUrl == null) {
      print('Failed to fetch server URL');
      return;
    }
  }
  setState(() {
    isLoading = true;
    isCaptureInProgress = true;
  });

  try {
    if (!isRecording) {
      // Start recording
      await _recorder!.startRecorder(toFile: 'audio.aac');
      setState(() {
        isRecording = true;
      });
    } else {
      // Stop recording and capture image
      audioPath = await _recorder!.stopRecorder();
      final image = await controller!.takePicture();
      final imageBytes = await image.readAsBytes();
      final audioBytes = await File(audioPath!).readAsBytes();

      final response = await http.post(
        Uri.parse('$serverUrl/uploads'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image': base64Encode(imageBytes),
          'audio': base64Encode(audioBytes),
        }),
      );

      if (response.statusCode == 200) {
        print('Upload successful');
      } else {
        print('Failed to upload');
      }
    }
  } catch (e) {
    print('Error during capture: $e');
  } finally {
    setState(() {
      isLoading = false;
      isCaptureInProgress = false;
    });
  }
}

  Future<void> retryCamera() async {
    setState(() {
      isCameraInitialized = false;
      imageUrl = null;
      responseText = null;
    });
    await initializeCamera();
  }

  @override
  void dispose() {
    controller?.dispose();
    flutterTts.stop();
    _recorder!.closeRecorder();
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
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            color: Colors.white,
            onPressed: retryCamera,
          ),
        ],
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
              Expanded(
                child: Center(
                  child: imageUrl == null
                      ? isCameraInitialized
                          ? CameraPreview(controller!)
                          : Container()
                      : Container(
                          width: double.infinity,
                          height: double.infinity,
                          child: Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: captureImageAndAudio,
                  child: Icon(isRecording ? Icons.stop : Icons.camera),
                ),
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