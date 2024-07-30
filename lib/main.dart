import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';

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
  FlutterTts flutterTts = FlutterTts();

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
      final image = await controller!.takePicture();
      final imageBytes = await image.readAsBytes();
      final response = await http.post(
        Uri.parse('http://192.168.1.4:5000/uploads'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Encode(imageBytes)}),
      );
      final responseData = jsonDecode(response.body);
      setState(() {
        imageUrl = responseData['image_url'];
        responseText = responseData['text'];
        isLoading = false;
      });
      await flutterTts.speak(responseText!);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
           appBar: AppBar(
        automaticallyImplyLeading: false, // this will hide the back button
        title: Center(
child: Text(
  'VisionAI',
  style: TextStyle(color: Colors.white),
), // replace 'Marks' with your desired title
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
                          : Container() // Empty container when camera is not initialized
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
          if (isLoading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}