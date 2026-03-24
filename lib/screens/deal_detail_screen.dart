import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/user_service.dart';

class DealDetailScreen extends StatefulWidget {
  final String title;
  final String description;
  final String price;
  final String category;
  final String? latitude;
  final String? longitude;
  final int? upvotes;
  final String? documentId;
  final String? userId;

  const DealDetailScreen({
    super.key,
    required this.title,
    required this.description,
    required this.price,
    required this.category,
    this.latitude,
    this.longitude,
    this.upvotes,
    this.documentId,
    this.userId,
  });

  @override
  State<DealDetailScreen> createState() => _DealDetailScreenState();
}

class _DealDetailScreenState extends State<DealDetailScreen> {
  int? _currentUpvotes;
  double? _distanceMeters;
  LatLng? _userLoc;
  bool _hasUpvoted = false;
  bool _isFavorite = false;
  bool _checkingUpvote = true;
  bool _checkingFavorite = true;

  @override
  void initState() {
    super.initState();
    _currentUpvotes = widget.upvotes ?? 0;
    _getUserLocationAndDistance();
    _checkIfUpvoted();
    _checkIfFavorite();
    _addToHistory(); // Add to history when viewing
  }

  Future<void> _getUserLocationAndDistance() async {
    if (widget.latitude == null || widget.longitude == null) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.always &&
            permission != LocationPermission.whileInUse) {
          return;
        }
      }
      final userPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _userLoc = LatLng(userPos.latitude, userPos.longitude);
      });
      final shopLat = double.tryParse(widget.latitude!);
      final shopLng = double.tryParse(widget.longitude!);
      if (shopLat != null && shopLng != null) {
        final distance = Geolocator.distanceBetween(
          userPos.latitude,
          userPos.longitude,
          shopLat,
          shopLng,
        );
        setState(() {
          _distanceMeters = distance;
        });
      }
    } catch (e) {
      // swallow, just don't show distance
    }
  }

  Future<void> _checkIfUpvoted() async {
    if (widget.userId == null || widget.documentId == null) return;
    final upvoted = await UserService.hasUpvoted(widget.userId!, widget.documentId!);
    setState(() {
      _hasUpvoted = upvoted;
      _checkingUpvote = false;
    });
  }

  Future<void> _checkIfFavorite() async {
    if (widget.userId == null || widget.documentId == null) return;
    final fav = await UserService.isFavorited(widget.userId!, widget.documentId!);
    setState(() {
      _isFavorite = fav;
      _checkingFavorite = false;
    });
  }

  Future<void> _addToHistory() async {
    if (widget.userId != null && widget.documentId != null) {
      await UserService.addToHistory(widget.userId!, widget.documentId!);
    }
  }

  Future<void> _toggleFavorite() async {
    if (widget.userId == null || widget.documentId == null) return;
    await UserService.toggleFavorite(widget.userId!, widget.documentId!);
    final fav = await UserService.isFavorited(widget.userId!, widget.documentId!);
    setState(() => _isFavorite = fav);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFavorite ? "Added to favorites" : "Removed from favorites"),
        backgroundColor: _isFavorite ? Colors.deepPurple : Colors.orange,
      ),
    );
  }

  Future<void> _upvoteDeal() async {
    if (widget.documentId == null ||
        widget.userId == null ||
        _hasUpvoted ||
        _checkingUpvote) return;
    try {
      final docRef = FirebaseFirestore.instance.collection('deals').doc(widget.documentId);
      await docRef.update({'upvotes': FieldValue.increment(1)});
      await UserService.recordUpvote(widget.userId!, widget.documentId!);
      setState(() {
        _currentUpvotes = (_currentUpvotes ?? 0) + 1;
        _hasUpvoted = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Upvoted! Thanks for your feedback."),
          backgroundColor: Colors.green,
        ),
      );
      _addToHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error upvoting: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopLat = widget.latitude != null ? double.tryParse(widget.latitude!) : null;
    final shopLng = widget.longitude != null ? double.tryParse(widget.longitude!) : null;
    final shopLoc = (shopLat != null && shopLng != null)
        ? LatLng(shopLat, shopLng)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deal Details'),
        backgroundColor: Colors.deepPurple.shade100,
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : Colors.deepPurple,
            ),
            onPressed: _checkingFavorite ? null : _toggleFavorite,
            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.description,
                      style: const TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.local_offer, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          widget.price,
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (shopLoc != null)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Location Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Shop Location: ${widget.latitude}, ${widget.longitude}",
                        style: const TextStyle(color: Colors.black87),
                      ),
                      if (_distanceMeters != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.directions, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              "Distance: ${(_distanceMeters! / 1000).toStringAsFixed(2)} km away",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (shopLoc != null)
              const SizedBox(height: 16),
            if (shopLoc != null)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: SizedBox(
                  height: 250,
                  child: FlutterMap(
                    options: MapOptions(
                      center: shopLoc,
                      zoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.dealnotifier',
                        maxZoom: 19,
                      ),
                      MarkerLayer(
                      markers: [
                        Marker(
                          width: 50,
                          height: 50,
                          point: shopLoc,
                          child: const Icon(
                            Icons.store,
                            color: Colors.orange,
                            size: 36,
                          ),
                        ),
                        if (_userLoc != null)
                          Marker(
                            width: 50,
                            height: 50,
                            point: _userLoc!,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 36,
                            ),
                          ),
                      ],
                    ),
                      if (_userLoc != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [_userLoc!, shopLoc],
                              color: Colors.blue,
                              strokeWidth: 3,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (shopLoc == null)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 10),
                child: Card(
                  color: Colors.yellow.shade50,
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.orange),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "No map location available for this deal.",
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.thumb_up, color: Colors.green, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          "Upvotes: $_currentUpvotes",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_checkingUpvote || _hasUpvoted)
                            ? null
                            : _upvoteDeal,
                        icon: Icon(_hasUpvoted ? Icons.check : Icons.thumb_up),
                        label:
                            Text(_hasUpvoted ? 'Already Upvoted' : 'Upvote This Deal'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasUpvoted ? Colors.grey : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}