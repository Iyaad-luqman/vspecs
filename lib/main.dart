import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    initializeCamera();
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

Future<void> captureImage() async {
  if (controller == null || !controller!.value.isInitialized) {
    print('Controller is not initialized');
    return;
  }
  if (isCaptureInProgress) {
    print('Capture already in progress');
    return;
  }
  setState(() {
    isLoading = true;
    isCaptureInProgress = true;
  });
  try {
    debugPrint('1 ---------------------->>>>>>>>');
    final image = await controller!.takePicture();
    debugPrint('2 ---------------------->>>>>>>>');
    final imageBytes = await image.readAsBytes();
    debugPrint('3 ---------------------->>>>>>>>');
    final response = await http.post(
      Uri.parse('http://192.168.1.4:5000/uploads'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image': base64Encode(imageBytes)}),
    );
    debugPrint('4 ---------------------->>>>>>>>');
    final responseData = jsonDecode(response.body);
    setState(() {
      imageUrl = responseData['image_url'];
      responseText = responseData['text'];
      isLoading = false;
    });
  } catch (e) {
    print('Error capturing image: $e');
    setState(() {
      isLoading = false;
    });
  } finally {
    setState(() {
      isCaptureInProgress = false;
    });
  }
}

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('VisionAI - Camera Mode'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: isLoading
                  ? CircularProgressIndicator()
                  : imageUrl == null
                      ? isCameraInitialized
                          ? CameraPreview(controller!)
                          : CircularProgressIndicator()
                      : Image.network(imageUrl!),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: captureImage,
              child: Icon(Icons.camera),
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
    );
  }
}
