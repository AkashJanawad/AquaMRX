import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart' as loc_pkg;
import 'package:camera/camera.dart';
// We "hide Size" here so it doesn't conflict with Flutter's button sizing
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'dart:async';
import 'dart:convert';

// --- CONFIGURATION ---
const String databaseUrl = 'https://aquamrx-ajway-default-rtdb.asia-southeast1.firebasedatabase.app/';
const String mapboxToken = 'pk.eyJ1IjoiYWthc2hhaiIsImEiOiJjbW54NWFjaXYwMHlhMnJzNm0xY2tvajAzIn0.jN3b3dgR6RrD5M7HnAEQ_w';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientation
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize Mapbox Access Token
  MapboxOptions.setAccessToken(mapboxToken);

  bool isInitialized = false;
  String? errorMessage;

  try {
    // Initialize Firebase
    await Firebase.initializeApp().timeout(const Duration(seconds: 20));
    // Get available cameras
    cameras = await availableCameras();
    isInitialized = true;
  } catch (e) {
    errorMessage = e.toString();
    debugPrint("Initialization Error: $e");
  }

  runApp(AquaMRXApp(isReady: isInitialized, error: errorMessage));
}

class AquaMRXApp extends StatelessWidget {
  final bool isReady;
  final String? error;
  const AquaMRXApp({super.key, required this.isReady, this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaMRX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0284C7)),
      ),
      home: isReady
          ? const ModeSelectionScreen()
          : Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text("Connection Error: $error\n\nTip: Check google-services.json and internet."),
          ),
        ),
      ),
    );
  }
}

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0EA5E9), Color(0xFF1E40AF)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.anchor_rounded, size: 80, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              "AQUA MRX",
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
            const SizedBox(height: 60),
            _btn(context, "CONTROLLER MODE", Icons.settings_remote, () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => const ControllerDashboard()));
            }),
            const SizedBox(height: 20),
            _btn(context, "PRODUCT MODE", Icons.directions_boat, () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => const ProductDashboard()));
            }, isPrimary: false),
          ],
        ),
      ),
    );
  }

  Widget _btn(BuildContext context, String txt, IconData icon, VoidCallback tap, {bool isPrimary = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ElevatedButton.icon(
        onPressed: tap,
        icon: Icon(icon),
        label: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 70), // This was causing the error
          backgroundColor: isPrimary ? Colors.white : Colors.white24,
          foregroundColor: isPrimary ? Colors.blue[900] : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// --- DASHBOARD: CONTROLLER (Remote User) ---
class ControllerDashboard extends StatefulWidget {
  const ControllerDashboard({super.key});
  @override
  State<ControllerDashboard> createState() => _ControllerDashboardState();
}

class _ControllerDashboardState extends State<ControllerDashboard> {
  late DatabaseReference _db;
  double tds = 0, ph = 0, temp = 0, lat = 0, lng = 0;
  String? base64Image;

  @override
  void initState() {
    super.initState();
    _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: databaseUrl).ref();

    // Telemetry Listener
    _db.child('telemetry').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        setState(() {
          tds = (data['tds'] ?? 0.0).toDouble();
          ph = (data['ph'] ?? 0.0).toDouble();
          temp = (data['temp'] ?? 0.0).toDouble();
          lat = (data['lat'] ?? 0.0).toDouble();
          lng = (data['lng'] ?? 0.0).toDouble();
        });
      }
    });

    // Visual Link Listener
    _db.child('visual_feed').onValue.listen((event) {
      final imgData = event.snapshot.value as String?;
      if (imgData != null && imgData.isNotEmpty) {
        setState(() => base64Image = imgData);
      }
    });
  }

  void _send(String d) => _db.child('commands').update({'direction': d});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Mission Control Center"), elevation: 0, backgroundColor: Colors.white),
      body: Column(
        children: [
          // 1. VIDEO FEED WINDOW
          Container(
            height: 240,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)]),
            clipBehavior: Clip.antiAlias,
            child: base64Image != null
                ? Image.memory(base64Decode(base64Image!), fit: BoxFit.cover, gaplessPlayback: true)
                : const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 48), SizedBox(height: 8), Text("Camera Feed Pending...", style: TextStyle(color: Colors.white38))],
            )),
          ),

          // 2. MAP ACCESS BUTTON
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => MapboxMapScreen(lat: lat, lng: lng)));
              },
              icon: const Icon(Icons.map_rounded),
              label: const Text("OPEN LIVE MAP (FULL SCREEN)"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60), // Conflict fixed by import hide
                backgroundColor: Colors.blue[50],
                foregroundColor: Colors.blue[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // 3. TELEMETRY STATS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                _stat("TDS", "$tds ppm", Colors.blue),
                _stat("pH", ph.toStringAsFixed(1), Colors.purple),
                _stat("Temp", "${temp}°C", Colors.orange),
              ],
            ),
          ),

          const Spacer(),
          _buildControls(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _stat(String l, String v, Color c) => Expanded(
    child: Card(
      elevation: 0,
      color: c.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.withOpacity(0.2))),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text(l, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
    ),
  );

  Widget _buildControls() {
    return Column(
      children: [
        _moveBtn(Icons.arrow_upward_rounded, "forward"),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _moveBtn(Icons.arrow_back_rounded, "left"),
          const SizedBox(width: 15),
          _moveBtn(Icons.stop_circle_rounded, "stop", color: Colors.redAccent),
          const SizedBox(width: 15),
          _moveBtn(Icons.arrow_forward_rounded, "right"),
        ]),
        _moveBtn(Icons.arrow_downward_rounded, "reverse"),
      ],
    );
  }

  Widget _moveBtn(IconData i, String d, {Color color = Colors.blue}) =>
      IconButton(icon: Icon(i, color: color, size: 60), onPressed: () => _send(d));
}

// --- NEW SCREEN: FULL SCREEN MAPBOX MAP ---
class MapboxMapScreen extends StatefulWidget {
  final double lat;
  final double lng;
  const MapboxMapScreen({super.key, required this.lat, required this.lng});

  @override
  State<MapboxMapScreen> createState() => _MapboxMapScreenState();
}

class _MapboxMapScreenState extends State<MapboxMapScreen> {
  MapboxMap? mapboxMap;
  late DatabaseReference _db;
  PointAnnotationManager? pointAnnotationManager;
  double currentLat = 0;
  double currentLng = 0;

  @override
  void initState() {
    super.initState();
    currentLat = widget.lat;
    currentLng = widget.lng;
    _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: databaseUrl).ref();

    // Track live movement for the map
    _db.child('telemetry').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          currentLat = (data['lat'] ?? 0.0).toDouble();
          currentLng = (data['lng'] ?? 0.0).toDouble();
        });
        _updateMarker();
      }
    });
  }

  _onMapCreated(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;
    mapboxMap.annotations.createPointAnnotationManager().then((value) {
      pointAnnotationManager = value;
      _updateMarker();
    });
  }

  void _updateMarker() {
    if (pointAnnotationManager != null && currentLat != 0) {
      pointAnnotationManager!.deleteAll();
      pointAnnotationManager!.create(
          PointAnnotationOptions(
            geometry: Point(coordinates: Position(currentLng, currentLat)),
            iconImage: "marker-15",
            iconSize: 2.0,
          )
      );
      // Auto-center camera
      mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(currentLng, currentLat)), zoom: 16.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Boat Tracking")),
      body: MapWidget(
        onMapCreated: _onMapCreated,
        cameraOptions: CameraOptions(center: Point(coordinates: Position(currentLng, currentLat)), zoom: 12.0),
      ),
    );
  }
}

// --- DASHBOARD: PRODUCT (The Boat Hardware) ---
class ProductDashboard extends StatefulWidget {
  const ProductDashboard({super.key});
  @override
  State<ProductDashboard> createState() => _ProductDashboardState();
}

class _ProductDashboardState extends State<ProductDashboard> {
  late DatabaseReference _db;
  CameraController? camController;
  Timer? streamTimer;
  List<String> logs = [];
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: databaseUrl).ref();
    _initCamera();
    _startGateway();
  }

  void _initCamera() async {
    if (cameras.isEmpty) return;
    camController = CameraController(cameras[0], ResolutionPreset.low, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await camController!.initialize();
    if (!mounted) return;
    setState(() {});

    streamTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (_isProcessingImage) return;
      if (camController != null && camController!.value.isInitialized) {
        _isProcessingImage = true;
        try {
          final XFile file = await camController!.takePicture();
          final bytes = await file.readAsBytes();
          final base64String = base64Encode(bytes);
          if (base64String.length < 200000) {
            await _db.child('visual_feed').set(base64String);
          }
        } catch (e) {
          debugPrint("Capture error: $e");
        } finally {
          _isProcessingImage = false;
        }
      }
    });
  }

  void _startGateway() async {
    loc_pkg.Location location = loc_pkg.Location();
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) serviceEnabled = await location.requestService();

    loc_pkg.PermissionStatus permission = await location.hasPermission();
    if (permission == loc_pkg.PermissionStatus.denied) {
      permission = await location.requestPermission();
    }

    location.onLocationChanged.listen((l) {
      if (l.latitude != null && l.longitude != null) {
        _db.child('telemetry').update({'lat': l.latitude, 'lng': l.longitude});
      }
    });

    _db.child('commands').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        _relayToEsp(data['direction'] ?? "stop");
      }
    });
  }

  void _relayToEsp(String d) async {
    setState(() => logs.insert(0, "CMD: $d"));
    try {
      await http.get(Uri.parse("http://192.168.4.1/move?dir=$d")).timeout(const Duration(milliseconds: 400));
    } catch (_) {}
  }

  @override
  void dispose() {
    streamTimer?.cancel();
    camController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (camController != null && camController!.value.isInitialized)
            Positioned.fill(child: CameraPreview(camController!))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),

          Positioned(
            bottom: 30, left: 20, right: 20,
            child: Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (c, i) => Text(logs[i], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 10)),
              ),
            ),
          ),
          Positioned(top: 50, left: 20, child: CircleAvatar(backgroundColor: Colors.black54, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)))),
        ],
      ),
    );
  }
}