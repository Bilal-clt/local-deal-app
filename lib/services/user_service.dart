import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Toggle favorite logic
  static Future<void> toggleFavorite(String userId, String dealId) async {
    try {
      final favoriteRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(dealId);
      
      final favoriteDoc = await favoriteRef.get();
      
      if (favoriteDoc.exists) {
        await favoriteRef.delete();
        await _firestore.collection('users').doc(userId).update({
          'favoritesCount': FieldValue.increment(-1),
        });
      } else {
        final dealDoc = await _firestore.collection('deals').doc(dealId).get();
        if (dealDoc.exists) {
          final dealData = dealDoc.data()!;
          await favoriteRef.set({
            'dealId': dealId,
            'title': dealData['title'] ?? '',
            'description': dealData['description'] ?? '',
            'price': dealData['price'] ?? '',
            'category': dealData['category'] ?? '',
            'latitude': dealData['latitude'],
            'longitude': dealData['longitude'],
            'upvotes': dealData['upvotes'] ?? 0,
            'shopName': dealData['shopName'] ?? '',
            'addedAt': FieldValue.serverTimestamp(),
          });
          await _firestore.collection('users').doc(userId).update({
            'favoritesCount': FieldValue.increment(1),
          });
        }
      }
    } catch (e) {
      print('Error toggling favorite: $e');
    }
  }

  static Future<bool> isFavorited(String userId, String dealId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(dealId)
          .get();
      return doc.exists;
    } catch (e) {
      print('Error checking favorite status: $e');
      return false;
    }
  }

  static Stream<QuerySnapshot> getUserFavorites(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('favorites')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  // Add to history, also marks "active day" for user
  static Future<void> addToHistory(String userId, String dealId) async {
    try {
      final dealDoc = await _firestore.collection('deals').doc(dealId).get();
      if (dealDoc.exists) {
        final dealData = dealDoc.data()!;
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('history')
            .doc(dealId)
            .set({
          'dealId': dealId,
          'title': dealData['title'] ?? '',
          'description': dealData['description'] ?? '',
          'price': dealData['price'] ?? '',
          'category': dealData['category'] ?? '',
          'latitude': dealData['latitude'],
          'longitude': dealData['longitude'],
          'upvotes': dealData['upvotes'] ?? 0,
          'shopName': dealData['shopName'] ?? '',
          'viewedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        await _firestore.collection('users').doc(userId).update({
          'dealsViewed': FieldValue.increment(1),
        });
        
        // Add unique day for active_days collection
        await _markActiveDay(userId);
      }
    } catch (e) {
      print('Error adding to history: $e');
    }
  }

  static Stream<QuerySnapshot> getUserHistory(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('history')
        .orderBy('viewedAt', descending: true)
        .limit(50)
        .snapshots();
  }

  // Upvote logic, also marks "active day" for user
  static Future<void> recordUpvote(String userId, String dealId) async {
    try {
      final upvoteRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('upvotes')
          .doc(dealId);
      
      final upvoted = await upvoteRef.get();
      
      if (!upvoted.exists) {
        await _firestore.collection('users').doc(userId).update({
          'upvotesGiven': FieldValue.increment(1),
        });
        
        await upvoteRef.set({
          'dealId': dealId,
          'upvotedAt': FieldValue.serverTimestamp(),
        });
      }
      
      // Also mark as active day
      await _markActiveDay(userId);
    } catch (e) {
      print('Error recording upvote: $e');
    }
  }

  static Future<bool> hasUpvoted(String userId, String dealId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('upvotes')
          .doc(dealId)
          .get();
      return doc.exists;
    } catch (e) {
      print('Error checking upvote status: $e');
      return false;
    }
  }

  // Helper method to mark active day
  static Future<void> _markActiveDay(String userId) async {
    try {
      final now = DateTime.now();
      final day = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('active_days')
          .doc(day)
          .set({'date': day}, SetOptions(merge: true));
    } catch (e) {
      print('Error marking active day: $e');
    }
  }

  /// User profile stats: robust unique days active count
  static Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      // Get all unique days from active_days subcollection
      final activeDaysSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('active_days')
          .get();
      
      final Set<String> uniqueDays = activeDaysSnap.docs
          .map((e) => e.id)
          .where((e) => e.contains('-')) // yyyy-mm-dd format
          .toSet();

      final userDoc = await _firestore.collection('users').doc(userId).get();
      Map<String, dynamic> userData = {};
      
      if (userDoc.exists) {
        userData = userDoc.data()!;
      }
      
      return {
        'favoritesCount': userData['favoritesCount'] ?? 0,
        'upvotesGiven': userData['upvotesGiven'] ?? 0,
        'dealsViewed': userData['dealsViewed'] ?? 0,
        'daysActive': uniqueDays.length,
      };
    } catch (e) {
      print('Error getting user stats: $e');
      return {
        'favoritesCount': 0,
        'upvotesGiven': 0,
        'dealsViewed': 0,
        'daysActive': 0,
      };
    }
  }
}