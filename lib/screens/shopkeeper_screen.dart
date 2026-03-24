import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class ShopkeeperScreen extends StatefulWidget {
  final User user;
  const ShopkeeperScreen({super.key, required this.user});

  @override
  State<ShopkeeperScreen> createState() => _ShopkeeperScreenState();
}

class _ShopkeeperScreenState extends State<ShopkeeperScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  Map<String, dynamic>? _shopLocation;
  bool _locLoading = false;

  final List<_ExpiryOption> _expiryOptions = [
    _ExpiryOption('1 Day', 1),
    _ExpiryOption('3 Days', 3),
    _ExpiryOption('1 Week', 7),
    _ExpiryOption('2 Weeks', 14),
    _ExpiryOption('1 Month', 30),
  ];
  _ExpiryOption _selectedExpiry = _ExpiryOption('1 Week', 7);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  bool _shopNameDialogOpen = false;
  String? _shopName;

  static const List<String> _categories = [
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
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _getOrSetShopLocation();
    _fetchShopName();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  void _showCustomSnackBar(String message, Color backgroundColor, {IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _getOrSetShopLocation() async {
    setState(() => _locLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shopkeepers')
          .doc(widget.user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _shopLocation = {
            'latitude': data['latitude'],
            'longitude': data['longitude'],
          };
          _locLoading = false;
        });
        return;
      }
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        final reqPerm = await Geolocator.requestPermission();
        if (reqPerm != LocationPermission.always && reqPerm != LocationPermission.whileInUse) {
          setState(() => _locLoading = false);
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await FirebaseFirestore.instance
          .collection('shopkeepers')
          .doc(widget.user.uid)
          .set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'shopkeeperUid': widget.user.uid,
      });
      setState(() {
        _shopLocation = {'latitude': pos.latitude, 'longitude': pos.longitude};
        _locLoading = false;
      });
    } catch (_) {
      setState(() => _locLoading = false);
    }
  }

  Future<void> _resetLocation() async {
    setState(() => _locLoading = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        final reqPerm = await Geolocator.requestPermission();
        if (reqPerm != LocationPermission.always && reqPerm != LocationPermission.whileInUse) {
          setState(() => _locLoading = false);
          _showCustomSnackBar('Location permission denied!', Colors.red, icon: Icons.error);
          return;
        }
      }
      
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      await FirebaseFirestore.instance
          .collection('shopkeepers')
          .doc(widget.user.uid)
          .set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'shopkeeperUid': widget.user.uid,
      });
      
      setState(() {
        _shopLocation = {'latitude': pos.latitude, 'longitude': pos.longitude};
        _locLoading = false;
      });
      
      _showCustomSnackBar('Location updated successfully!', Colors.green, icon: Icons.location_on);
    } catch (e) {
      setState(() => _locLoading = false);
      _showCustomSnackBar('Failed to update location: $e', Colors.red, icon: Icons.error);
    }
  }

  Future<void> _fetchShopName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final shopName = doc.data()!['shopName'] as String?;
        setState(() {
          _shopName = shopName;
          if (_shopName != null) _shopNameController.text = _shopName!;
        });
      }
      if (_shopName == null && !_shopNameDialogOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showShopNameDialog();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveShopName(String value) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .set(
      {'shopName': value.trim()},
      SetOptions(merge: true),
    );
    setState(() {
      _shopName = value.trim();
      _shopNameController.text = value.trim();
    });
    if (mounted) {
      Navigator.of(context).pop();
      _shopNameDialogOpen = false;
    }
  }

  void _showShopNameDialog() {
    if (!mounted) return;
    _shopNameDialogOpen = true;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Enter Your Shop Name"),
        content: TextField(
          controller: _shopNameController,
          decoration: const InputDecoration(hintText: "Shop Name"),
          autofocus: true,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              final text = _shopNameController.text.trim();
              if (text.isEmpty) return;
              _saveShopName(text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadDeal() async {
    if (_formKey.currentState?.validate() != true) return;

    if (_shopLocation == null) {
      _showCustomSnackBar('Shop location not set!', Colors.red, icon: Icons.error);
      return;
    }

    if (_shopNameController.text.trim().isEmpty) {
      _showShopNameDialog();
      return;
    }

    if (_selectedCategory == null) {
      _showCustomSnackBar('Please choose a category.', Colors.red, icon: Icons.error);
      return;
    }

    setState(() => _loading = true);

    try {
      final expiryDate = DateTime.now().add(Duration(days: _selectedExpiry.days));
      await FirebaseFirestore.instance.collection('deals').add({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': _priceController.text.trim(),
        'latitude': _shopLocation!['latitude'],
        'longitude': _shopLocation!['longitude'],
        'upvotes': 0,
        'shopkeeperUid': widget.user.uid,
        'shopName': _shopNameController.text.trim(),
        'category': _selectedCategory!,
        'expiryDate': Timestamp.fromDate(expiryDate),
        'timestamp': Timestamp.now(),
      });

      if (mounted) {
        // Clear all form fields
        _titleController.clear();
        _descriptionController.clear();
        _priceController.clear();
        setState(() {
          _selectedExpiry = _expiryOptions[2]; // Reset to 1 Week
          _selectedCategory = null;
        });
        _formKey.currentState?.reset();
        _showCustomSnackBar('Deal uploaded successfully!', Colors.green, icon: Icons.check_circle);
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar('Error uploading deal: $e', Colors.red, icon: Icons.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar('Sign out failed: $e', Colors.red, icon: Icons.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopkeeper Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.deepPurple,
              backgroundImage: widget.user.photoURL != null && widget.user.photoURL!.isNotEmpty
                  ? NetworkImage(widget.user.photoURL!)
                  : null,
              child: widget.user.photoURL == null || widget.user.photoURL!.isEmpty
                  ? Text(
                      widget.user.displayName?.isNotEmpty == true
                          ? widget.user.displayName![0].toUpperCase()
                          : widget.user.email?.isNotEmpty == true
                              ? widget.user.email![0].toUpperCase()
                              : 'U',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'reset_location') {
                _resetLocation();
              } else if (value == 'set_shop_name') {
                _showShopNameDialog();
              } else if (value == 'logout') {
                _signOut(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset_location',
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Reset Location'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'set_shop_name',
                child: Row(
                  children: [
                    Icon(Icons.store, color: Colors.deepPurple),
                    SizedBox(width: 8),
                    Text('Set Shop Name'),
                  ],
                ),
              ),
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
      body: _locLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_shopName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.store, color: Colors.deepPurple),
                          const SizedBox(width: 10),
                          Text(
                            "Shop: $_shopName",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            const Text(
                              'Add New Deal',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _titleController,
                              decoration: const InputDecoration(labelText: 'Title'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Title required' : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _descriptionController,
                              decoration: const InputDecoration(labelText: 'Description'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Description required' : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _priceController,
                              decoration: const InputDecoration(labelText: 'Price'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Price required' : null,
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                              ),
                              value: _selectedCategory,
                              items: _categories
                                  .map((cat) => DropdownMenuItem<String>(
                                        value: cat,
                                        child: Text(cat),
                                      ))
                                  .toList(),
                              onChanged: (cat) => setState(() => _selectedCategory = cat),
                              validator: (v) => v == null || v.isEmpty ? 'Please select a category.' : null,
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<_ExpiryOption>(
                              value: _selectedExpiry,
                              decoration: const InputDecoration(
                                labelText: 'Expiry Duration',
                                border: OutlineInputBorder(),
                              ),
                              items: _expiryOptions.map((option) {
                                return DropdownMenuItem<_ExpiryOption>(
                                  value: option,
                                  child: Text(option.label),
                                );
                              }).toList(),
                              onChanged: (option) {
                                if (option != null) setState(() => _selectedExpiry = option);
                              },
                            ),
                            const SizedBox(height: 18),
                            _loading
                                ? const CircularProgressIndicator()
                                : ElevatedButton.icon(
                                    icon: const Icon(Icons.upload),
                                    label: const Text('Upload Deal'),
                                    onPressed: _uploadDeal,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurple,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Your Deals',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                  ),
                  const SizedBox(height: 10),
                  _ShopkeeperDealsList(shopkeeperUid: widget.user.uid),
                ],
              ),
            ),
    );
  }
}

class _ShopkeeperDealsList extends StatelessWidget {
  final String shopkeeperUid;
  const _ShopkeeperDealsList({required this.shopkeeperUid});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deals')
          .where('shopkeeperUid', isEqualTo: shopkeeperUid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text("Error loading deals. Please try again."),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text("No deals uploaded yet."),
          );
        }
        // FIXED VERSION:
        final filtered = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          
          // Get expiry date
          DateTime? expiry;
          if (data['expiryDate'] != null) {
            if (data['expiryDate'] is Timestamp) {
              expiry = (data['expiryDate'] as Timestamp).toDate();
            } else if (data['expiryDate'] is DateTime) {
              expiry = data['expiryDate'] as DateTime;
            }
          }
          
          // If no expiry date, calculate from timestamp (fallback)
          if (expiry == null && data['timestamp'] != null) {
            if (data['timestamp'] is Timestamp) {
              expiry = (data['timestamp'] as Timestamp).toDate().add(const Duration(days: 7));
            } else if (data['timestamp'] is DateTime) {
              expiry = (data['timestamp'] as DateTime).add(const Duration(days: 7));
            }
          }
          
          // If still no expiry, show the deal (don't filter it out)
          if (expiry == null) {
            return true; // THIS IS THE KEY FIX!
          }
          
          // Only show deals that haven't expired
          return expiry.isAfter(now);
        }).toList();

        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text("No active deals."),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final doc = filtered[idx];
            final data = doc.data() as Map<String, dynamic>;
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        data['title'] ?? 'No Title',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if ((data['shopName'] ?? '').toString().isNotEmpty)
                      Flexible(
                        child: Text(
                          data['shopName'],
                          style: const TextStyle(
                              color: Colors.deepPurple, fontWeight: FontWeight.w500, fontSize: 14),
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['description'] ?? 'No Description'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if ((data['category'] ?? '').toString().isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Text(data['category'], style: const TextStyle(color: Colors.deepPurple)),
                          ),
                        const SizedBox(width: 6),
                        _ExpiryText(expiryDate: data['expiryDate'], timestamp: data['timestamp']),
                      ],
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.thumb_up, color: Colors.green, size: 20),
                    Text(
                      '${data['upvotes'] ?? 0}',
                      style: TextStyle(color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ExpiryOption {
  final String label;
  final int days;
  const _ExpiryOption(this.label, this.days);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _ExpiryOption && runtimeType == other.runtimeType && days == other.days;

  @override
  int get hashCode => days.hashCode;
}

class _ExpiryText extends StatelessWidget {
  final dynamic expiryDate;
  final dynamic timestamp;

  const _ExpiryText({super.key, this.expiryDate, this.timestamp});
  @override
  Widget build(BuildContext context) {
    DateTime? expiry;
    if (expiryDate != null) {
      if (expiryDate is Timestamp) {
        expiry = (expiryDate as Timestamp).toDate();
      } else if (expiryDate is DateTime) {
        expiry = expiryDate;
      }
    } else if (timestamp != null) {
      if (timestamp is Timestamp) {
        expiry = (timestamp as Timestamp).toDate().add(const Duration(days: 7));
      } else if (timestamp is DateTime) {
        expiry = timestamp.add(const Duration(days: 7));
      }
    }
    if (expiry == null) {
      return const Text("No expiry info", style: TextStyle(color: Colors.orange));
    }
    final now = DateTime.now();
    final diff = expiry.difference(now).inDays;
    final todayDiff = expiry.difference(now).inHours;
    if (expiry.isBefore(now)) {
      return const Text("Expired", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold));
    } else if (diff == 0 || todayDiff < 24) {
      return const Text("Expires today", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));
    } else {
      return Text(
        "Expires in $diff days",
        style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w500),
      );
    }
  }
}