import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class SearchFilterService {
  // Instead of filtering in the stream, get all deals and filter client-side
  static Stream<QuerySnapshot> getAllDeals() {
    return FirebaseFirestore.instance
        .collection('deals')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Client-side filtering method
  static List<DocumentSnapshot> filterDeals(
    List<DocumentSnapshot> deals, {
    String searchQuery = '',
    String category = 'All',
    double minPrice = 0,
    double maxPrice = 1000,
    double maxDistance = 50,
    Position? userPosition,
    bool debugMode = false,
  }) {
    if (debugMode) {
      print('\n=== SEARCH FILTER DEBUG ===');
      print('Total deals: ${deals.length}');
      print('Filters: search="$searchQuery", category="$category", price=$minPrice-$maxPrice, distance=$maxDistance');
    }

    final filteredDeals = deals.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      
      // Category filter
      if (category != 'All') {
        final dealCategory = (data['category'] ?? '').toString();
        if (dealCategory.isEmpty || dealCategory != category) {
          if (debugMode) print('❌ ${data['title']} - Category mismatch: "$dealCategory" != "$category"');
          return false;
        }
      }

      // Search filter  
      if (searchQuery.isNotEmpty) {
        final title = (data['title'] ?? '').toString().toLowerCase();
        final description = (data['description'] ?? '').toString().toLowerCase();
        final shopName = (data['shopName'] ?? '').toString().toLowerCase();
        final query = searchQuery.toLowerCase();
        
        if (!title.contains(query) && !description.contains(query) && !shopName.contains(query)) {
          if (debugMode) print('❌ ${data['title']} - Search mismatch: "$query" not in title/description/shop');
          return false;
        }
      }

      // Price filter
      final price = _extractNumericPrice(data['price']);
      if (price != null && (price < minPrice || price > maxPrice)) {
        if (debugMode) print('❌ ${data['title']} - Price out of range: $price not in $minPrice-$maxPrice');
        return false;
      }

      // Distance filter
      if (userPosition != null && data['latitude'] != null && data['longitude'] != null) {
        try {
          final lat = _parseDouble(data['latitude']);
          final lng = _parseDouble(data['longitude']);
          if (lat != null && lng != null) {
            final distance = Geolocator.distanceBetween(
              userPosition.latitude,
              userPosition.longitude,
              lat,
              lng,
            ) / 1000;
            if (distance > maxDistance) {
              if (debugMode) print('❌ ${data['title']} - Too far: ${distance.toStringAsFixed(1)}km > ${maxDistance}km');
              return false;
            }
          }
        } catch (e) {
          if (debugMode) print('❌ ${data['title']} - Distance calculation error: $e');
        }
      }

      if (debugMode) print('✅ ${data['title']} - INCLUDED');
      return true;
    }).toList();

    if (debugMode) {
      print('Filtered deals: ${filteredDeals.length}');
      print('===========================\n');
    }

    return filteredDeals;
  }

  // Helper method to calculate distance
  static double? calculateDistance(Map<String, dynamic> data, Position? userPosition) {
    if (userPosition == null || data['latitude'] == null || data['longitude'] == null) {
      return null;
    }
    
    try {
      final lat = _parseDouble(data['latitude']);
      final lng = _parseDouble(data['longitude']);
      if (lat != null && lng != null) {
        return Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          lat,
          lng,
        ) / 1000; // Convert to kilometers
      }
    } catch (e) {
      print('Error calculating distance: $e');
    }
    return null;
  }

  static double? _extractNumericPrice(dynamic priceData) {
    if (priceData == null) return null;
    if (priceData is num) return priceData.toDouble();
    if (priceData is String) {
      final numericString = priceData.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(numericString);
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}