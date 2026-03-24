import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<Map<String, dynamic>> getCompleteAnalytics() async {
    try {
      final results = await Future.wait([
        _getTotalDeals(),
        _getTotalViews(),
        _getTotalUpvotes(),
        _getActiveUsers(),
        _getTopDeals(),
        _getCategoryStats(),
        _getRecentActivity(),
      ]);
      return {
        'totalDeals': results[0],
        'totalViews': results[1],
        'totalUpvotes': results[2],
        'activeUsers': results[3],
        'topDeals': results[4],
        'categoryStats': results[5],
        'recentActivity': results[6],
      };
    } catch (e) {
      return _getEmptyAnalytics();
    }
  }

  static Future<int> _getTotalDeals() async {
    try {
      final snapshot = await _firestore.collection('deals').get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> _getTotalViews() async {
    try {
      final snapshot = await _firestore.collection('deals').get();
      int totalViews = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        totalViews += (data['views'] as int?) ?? 0;
      }
      return totalViews;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> _getTotalUpvotes() async {
    try {
      final snapshot = await _firestore.collection('deals').get();
      int totalUpvotes = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        totalUpvotes += (data['upvotes'] as int?) ?? 0;
      }
      return totalUpvotes;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> _getActiveUsers() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final snapshot = await _firestore
          .collection('users')
          .where('lastActiveAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> _getTopDeals() async {
    try {
      final snapshot = await _firestore
          .collection('deals')
          .orderBy('upvotes', descending: true)
          .limit(10)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Unknown',
          'upvotes': data['upvotes'] ?? 0,
          'views': data['views'] ?? 0,
          'price': data['price'] ?? 'N/A',
          'category': data['category'] ?? 'Other',
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> _getCategoryStats() async {
    try {
      final snapshot = await _firestore.collection('deals').get();
      final Map<String, Map<String, dynamic>> categoryStats = {};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final category = data['category'] ?? 'Other';
        final upvotes = (data['upvotes'] as int?) ?? 0;
        final views = (data['views'] as int?) ?? 0;
        if (!categoryStats.containsKey(category)) {
          categoryStats[category] = {
            'count': 0,
            'totalUpvotes': 0,
            'totalViews': 0,
            'avgUpvotes': 0,
          };
        }
        categoryStats[category]!['count'] = categoryStats[category]!['count'] + 1;
        categoryStats[category]!['totalUpvotes'] = categoryStats[category]!['totalUpvotes'] + upvotes;
        categoryStats[category]!['totalViews'] = categoryStats[category]!['totalViews'] + views;
      }
      categoryStats.forEach((category, stats) {
        final count = stats['count'] as int;
        if (count > 0) {
          stats['avgUpvotes'] = ((stats['totalUpvotes'] as int) / count).round();
        }
      });
      return Map<String, dynamic>.from(categoryStats);
    } catch (e) {
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> _getRecentActivity() async {
    try {
      final List<Map<String, dynamic>> activities = [];
      final recentDeals = await _firestore
          .collection('deals')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      for (var doc in recentDeals.docs) {
        final data = doc.data() as Map<String, dynamic>;
        activities.add({
          'type': 'deal_created',
          'title': data['title'] ?? 'Unknown Deal',
          'timestamp': data['createdAt'],
          'dealId': doc.id,
        });
      }
      final recentUsers = await _firestore
          .collection('users')
          .orderBy('lastActiveAt', descending: true)
          .limit(5)
          .get();
      for (var userDoc in recentUsers.docs) {
        final userId = userDoc.id;
        final upvotesSnapshot = await _firestore
            .collection('users')
            .doc(userId)
            .collection('upvotes')
            .orderBy('upvotedAt', descending: true)
            .limit(3)
            .get();
        for (var upvoteDoc in upvotesSnapshot.docs) {
          final upvoteData = upvoteDoc.data();
          final dealId = upvoteData['dealId'];
          final dealDoc = await _firestore.collection('deals').doc(dealId).get();
          if (dealDoc.exists) {
            final dealData = dealDoc.data()!;
            activities.add({
              'type': 'upvote',
              'title': dealData['title'] ?? 'Unknown Deal',
              'timestamp': upvoteData['upvotedAt'],
              'dealId': dealId,
            });
          }
        }
        final favoritesSnapshot = await _firestore
            .collection('users')
            .doc(userId)
            .collection('favorites')
            .orderBy('addedAt', descending: true)
            .limit(3)
            .get();
        for (var favoriteDoc in favoritesSnapshot.docs) {
          final favoriteData = favoriteDoc.data();
          activities.add({
            'type': 'favorite',
            'title': favoriteData['title'] ?? 'Unknown Deal',
            'timestamp': favoriteData['addedAt'],
            'dealId': favoriteData['dealId'],
          });
        }
      }
      activities.sort((a, b) {
        final aTime = a['timestamp'] as Timestamp?;
        final bTime = b['timestamp'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });
      return activities.take(20).toList();
    } catch (e) {
      return [];
    }
  }

  static Map<String, dynamic> _getEmptyAnalytics() {
    return {
      'totalDeals': 0,
      'totalViews': 0,
      'totalUpvotes': 0,
      'activeUsers': 0,
      'topDeals': <Map<String, dynamic>>[],
      'categoryStats': <String, dynamic>{},
      'recentActivity': <Map<String, dynamic>>[],
    };
  }
}