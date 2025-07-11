import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:photo_view/photo_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeSight',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _imageBase64;
  List<dynamic> _predictions = [];
  final ImagePicker _picker = ImagePicker();

  VideoPlayerController? _originalVideoController;
  VideoPlayerController? _processedVideoController;

  Future<void> pickImageAndSend() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);

    setState(() {
      _imageBase64 = null;
      _predictions = [];
      _originalVideoController?.dispose();
      _processedVideoController?.dispose();
      _originalVideoController = null;
      _processedVideoController = null;
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://10.0.2.2:5001/predict'),
    );
    request.files.add(await http.MultipartFile.fromPath('image', file.path));

    final response = await request.send();
    final resBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final data = json.decode(resBody);
      setState(() {
        _predictions = data['predictions'];
        _imageBase64 = data['image_base64'];
      });
    } else {
      print('API Hatası: ${response.statusCode}');
    }
  }

  Future<void> pickVideoAndSend() async {
    final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);

    _originalVideoController?.dispose();
    _processedVideoController?.dispose();

    _originalVideoController = VideoPlayerController.file(file);
    await _originalVideoController!.initialize();
    _originalVideoController!.setLooping(true);
    _originalVideoController!.play();

    setState(() {
      _imageBase64 = null;
      _predictions = [];
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://10.0.2.2:5001/video_predict'),
    );
    request.files.add(await http.MultipartFile.fromPath('video', file.path));

    final response = await request.send();
    final bytes = await response.stream.toBytes();

    if (response.statusCode == 200) {
      final tempFile = File('${Directory.systemTemp.path}/processed_video.mp4');
      await tempFile.writeAsBytes(bytes);

      _processedVideoController = VideoPlayerController.file(tempFile);
      await _processedVideoController!.initialize();
      _processedVideoController!.setLooping(false);
      _processedVideoController!.play();

      setState(() {});
    } else {
      print('Video API hatası: ${response.statusCode}');
    }
  }

  @override
  void dispose() {
    _originalVideoController?.dispose();
    _processedVideoController?.dispose();
    super.dispose();
  }

  Widget buildVideoWithControls(VideoPlayerController controller) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_10),
              onPressed: () {
                final pos = controller.value.position - const Duration(seconds: 10);
                controller.seekTo(pos > Duration.zero ? pos : Duration.zero);
              },
            ),
            IconButton(
              icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.forward_10),
              onPressed: () {
                final pos = controller.value.position + const Duration(seconds: 10);
                controller.seekTo(pos < controller.value.duration ? pos : controller.value.duration);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget buildIconButton({required String text, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.blue.shade100,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: Colors.blue.shade900),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
            ),
          ],
        ),
      ),
    );
  }

  Color getColorForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'sivil':
        return Colors.green.shade700;
      case 'silah':
        return Colors.blue.shade700;
      case 'silahli':
        return Colors.red.shade700;
      default:
        return Colors.black87;
    }
  }

  void showZoomableImage() {
    if (_imageBase64 == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: PhotoView(
            imageProvider: MemoryImage(base64Decode(_imageBase64!)),
            backgroundDecoration: const BoxDecoration(color: Colors.white),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚨 Silah Tespiti'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Görsel varsa göster
            if (_imageBase64 != null)
              GestureDetector(
                onTap: showZoomableImage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(base64Decode(_imageBase64!)),
                ),
              )
            else
              const Icon(Icons.image_outlined, size: 100, color: Colors.grey),

            const SizedBox(height: 16),

            // Video orijinal & işlenmiş varsa göster
            if (_originalVideoController != null && _originalVideoController!.value.isInitialized) ...[
              const Text('🎥 Orijinal Video', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              buildVideoWithControls(_originalVideoController!),
              const SizedBox(height: 16),
            ],
            if (_processedVideoController != null && _processedVideoController!.value.isInitialized) ...[
              const Text('📤 İşlenmiş Video', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              buildVideoWithControls(_processedVideoController!),
              const SizedBox(height: 16),
            ],

            // Model Tahminleri buraya geldi - butonların üstüne
            const Divider(height: 32),
            const Text('🧾 Model Tahminleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            if (_predictions.isEmpty)
              const Text("Henüz tahmin yapılmadı.")
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _predictions.map((pred) {
                  final label = pred['label'];
                  final confidence = pred['confidence'];
                  final box = pred['box'];
                  final color = getColorForLabel(label);

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Text(
                      "$label (${(confidence * 100).toStringAsFixed(1)}%) - [$box]",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 20),

            // Butonlar en altta
            buildIconButton(text: 'Görsel Seç ve Gönder', icon: Icons.photo, onTap: pickImageAndSend),
            buildIconButton(text: 'Video Seç ve Gönder', icon: Icons.video_collection, onTap: pickVideoAndSend),
            buildIconButton(
              text: 'Canlı Yayını Başlat',
              icon: Icons.videocam,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LiveStreamScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class LiveStreamScreen extends StatelessWidget {
  const LiveStreamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canlı Kamera Yayını')),
      body: Center(
        child: Mjpeg(
          stream: 'http://10.0.2.2:5001/live_predict',
          isLive: true,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}


