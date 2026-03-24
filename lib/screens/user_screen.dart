import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'deal_detail_screen.dart';
import 'user_profile_screen.dart';
import '../services/user_service.dart';

class UserScreen extends StatefulWidget {
  final User user;
  const UserScreen({super.key, required this.user});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  double _minPrice = 0;
  double _maxPrice = 1000;
  double _maxDistance = 30000; // Show all by default!
  Position? _userPosition;
  bool _isLoadingLocation = false;
  Timer? _debounceTimer;

  final List<String> _categories = [
    'All',
    'Food',
    'Clothing',
    'Electronics',
    'Home & Garden',
    'Sports & Recreation',
    'Books & Media',
    'Health & Beauty',
    'Automotive',
    'Services',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        _userPosition = await Geolocator.getCurrentPosition();
      }
    } catch (e) {
      print('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sign out failed: $e")),
        );
      }
    }
  }

  void _showFilterDialog() {
    String dialogCategory = _selectedCategory;
    double dialogMinPrice = _minPrice;
    double dialogMaxPrice = _maxPrice;
    double dialogMaxDistance = _maxDistance;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Deals'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: dialogCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories.map((category) => DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => dialogCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text('Price Range: \$${dialogMinPrice.toInt()} - \$${dialogMaxPrice.toInt()}'),
                RangeSlider(
                  values: RangeValues(dialogMinPrice, dialogMaxPrice),
                  min: 0,
                  max: 1000,
                  divisions: 20,
                  onChanged: (values) {
                    setDialogState(() {
                      dialogMinPrice = values.start;
                      dialogMaxPrice = values.end;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text('Max Distance: ${dialogMaxDistance.toInt()} km'),
                Slider(
                  value: dialogMaxDistance,
                  min: 1,
                  max: 30000,
                  divisions: 299,
                  onChanged: (value) {
                    setDialogState(() => dialogMaxDistance = value);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedCategory = 'All';
                _minPrice = 0;
                _maxPrice = 1000;
                _maxDistance = 30000;
              });
              Navigator.of(context).pop();
            },
            child: const Text('Reset'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedCategory = dialogCategory;
                _minPrice = dialogMinPrice;
                _maxPrice = dialogMaxPrice;
                _maxDistance = dialogMaxDistance;
              });
              Navigator.of(context).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  String _getLeadingShopNameLetter(Map<String, dynamic> data) {
    if (data.containsKey('shopName') &&
        data['shopName'] != null &&
        (data['shopName'] as String).isNotEmpty) {
      return data['shopName'][0].toUpperCase();
    }
    if (data.containsKey('title') &&
        data['title'] != null &&
        (data['title'] as String).isNotEmpty) {
      return data['title'][0].toUpperCase();
    }
    return 'D';
  }

  double? _calculateDistance(Map<String, dynamic> data) {
    if (_userPosition == null ||
        data['latitude'] == null ||
        data['longitude'] == null) {
      return null;
    }
    try {
      final lat = _parseDouble(data['latitude']);
      final lng = _parseDouble(data['longitude']);
      if (lat != null && lng != null) {
        return Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          lat,
          lng,
        ) / 1000; // km
      }
    } catch (e) {
      print('Error calculating distance: $e');
    }
    return null;
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double _parsePrice(dynamic priceData) {
    if (priceData == null) return 0;
    if (priceData is num) return priceData.toDouble();
    if (priceData is String) {
      String cleanPrice = priceData.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleanPrice) ?? 0;
    }
    return 0;
  }

  bool _isDealActive(Map<String, dynamic> data) {
    DateTime now = DateTime.now();
    DateTime? expiry;
    if (data['expiryDate'] != null) {
      if (data['expiryDate'] is Timestamp) {
        expiry = (data['expiryDate'] as Timestamp).toDate();
      } else if (data['expiryDate'] is DateTime) {
        expiry = data['expiryDate'];
      }
    } else if (data['timestamp'] != null) {
      // Default expiry: 7 days after timestamp
      if (data['timestamp'] is Timestamp) {
        expiry = (data['timestamp'] as Timestamp).toDate().add(const Duration(days: 7));
      } else if (data['timestamp'] is DateTime) {
        expiry = data['timestamp'].add(const Duration(days: 7));
      }
    }
    // If can't determine, consider active for safety
    if (expiry == null) return true;
    return expiry.isAfter(now);
  }

  List<DocumentSnapshot> _applyClientSideFilters(List<DocumentSnapshot> deals) {
    print("=== SEARCH FILTER DEBUG ===");
    print("Total deals: ${deals.length}");
    print('Filters: search="$_searchQuery", category="$_selectedCategory", price=$_minPrice-$_maxPrice, distance=$_maxDistance');
    int included = 0;
    final filtered = deals.where((deal) {
      final data = deal.data() as Map<String, dynamic>;

      // Expiry filter
      if (!_isDealActive(data)) {
        print('❌ ${data['title'] ?? '(unknown)'} - Expired');
        return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final title = (data['title'] ?? '').toString().toLowerCase();
        final description = (data['description'] ?? '').toString().toLowerCase();
        final shopName = (data['shopName'] ?? '').toString().toLowerCase();
        if (!title.contains(_searchQuery) &&
            !description.contains(_searchQuery) &&
            !shopName.contains(_searchQuery)) {
          print('❌ ${data['title'] ?? '(unknown)'} - Search mismatch');
          return false;
        }
      }
      // Category filter
      if (_selectedCategory != 'All') {
        final category = (data['category'] ?? '').toString();
        if (category != _selectedCategory) {
          print('❌ ${data['title'] ?? '(unknown)'} - Category mismatch');
          return false;
        }
      }
      // Price filter
      final price = _parsePrice(data['price']);
      if (price > 0 && (price < _minPrice || price > _maxPrice)) {
        print('❌ ${data['title'] ?? '(unknown)'} - Price out of range: $price not in $_minPrice-$_maxPrice');
        return false;
      }
      // Distance filter
      if (_userPosition != null) {
        final distance = _calculateDistance(data);
        if (distance != null && distance > _maxDistance) {
          print('❌ ${data['title'] ?? '(unknown)'} - Too far: $distance > $_maxDistance');
          return false;
        }
      }
      print('✅ ${data['title'] ?? '(unknown)'} - INCLUDED');
      included++;
      return true;
    }).toList();
    print("Filtered deals: $included");
    return filtered;
  }

  Future<void> _onDealTap(DocumentSnapshot deal) async {
    try {
      final data = deal.data() as Map<String, dynamic>;
      await UserService.addToHistory(widget.user.uid, deal.id);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DealDetailScreen(
              title: data['title'] ?? 'No Title',
              description: data['description'] ?? 'No Description',
              price: data['price'] ?? 'No Price',
              category: data['category'] ?? 'Other',
              latitude: data['latitude']?.toString(),
              longitude: data['longitude']?.toString(),
              upvotes: data['upvotes'] ?? 0,
              documentId: deal.id,
              userId: widget.user.uid,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error handling deal tap: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening deal: $e')),
        );
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _searchQuery = value.toLowerCase());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Deals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(user: widget.user),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'logout') {
                _signOut(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search deals...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showFilterDialog,
                        icon: const Icon(Icons.filter_list),
                        label: Text('Filter ${_selectedCategory != 'All' ? '(${_selectedCategory})' : ''}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade100,
                          foregroundColor: Colors.deepPurple,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isLoadingLocation)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        onPressed: _getUserLocation,
                        icon: Icon(
                          Icons.my_location,
                          color: _userPosition != null ? Colors.green : Colors.grey,
                        ),
                        tooltip: _userPosition != null
                            ? 'Location enabled'
                            : 'Enable location for distance filtering',
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('deals')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                print("Firebase returned ${snapshot.data!.docs.length} deals");
                final filteredDeals = _applyClientSideFilters(snapshot.data!.docs);
                if (filteredDeals.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text("No deals found matching your criteria."),
                        SizedBox(height: 8),
                        Text(
                          "Try adjusting your filters or search terms.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filteredDeals.length,
                  itemBuilder: (context, index) {
                    final deal = filteredDeals[index];
                    final data = deal.data() as Map<String, dynamic>;
                    final distance = _calculateDistance(data);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: (data['shopName'] != null && (data['shopName'] as String).isNotEmpty)
                            ? CircleAvatar(
                                backgroundColor: Colors.deepPurple.shade100,
                                child: Text(
                                  _getLeadingShopNameLetter(data),
                                  style: TextStyle(
                                    color: Colors.deepPurple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                backgroundColor: Colors.deepPurple.shade100,
                                child: Icon(Icons.store, color: Colors.deepPurple),
                              ),
                        title: Text(
                          data['title'] ?? 'No Title',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['description'] ?? 'No Description',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((data['shopName'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.store, color: Colors.deepPurple, size: 16),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        data['shopName'],
                                        style: const TextStyle(
                                          color: Colors.deepPurple,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  data['price'] ?? 'No Price',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (distance != null)
                                  Text(
                                    '${distance.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                  ),
                                if ((data['category'] ?? '').toString().isNotEmpty)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.deepPurple.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Text(
                                      data['category'],
                                      style: const TextStyle(
                                        color: Colors.deepPurple,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                if (_isDealActive(data) && data['expiryDate'] != null)
                                  Builder(
                                    builder: (_) {
                                      DateTime? expiry;
                                      if (data['expiryDate'] is Timestamp) {
                                        expiry = (data['expiryDate'] as Timestamp).toDate();
                                      } else if (data['expiryDate'] is DateTime) {
                                        expiry = data['expiryDate'];
                                      }
                                      if (expiry != null) {
                                        final now = DateTime.now();
                                        final diff = expiry.difference(now).inDays;
                                        final hours = expiry.difference(now).inHours;
                                        if (expiry.isBefore(now)) {
                                          return const Text("Expired", style: TextStyle(color: Colors.red));
                                        } else if (diff == 0 || hours < 24) {
                                          return const Text("Expires today", style: TextStyle(color: Colors.orange));
                                        } else {
                                          return Text("Expires in $diff days",
                                              style: const TextStyle(color: Colors.deepPurple));
                                        }
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.thumb_up, color: Colors.green, size: 18),
                            const SizedBox(height: 2),
                            Text(
                              '${data['upvotes'] ?? 0}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _onDealTap(deal),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}