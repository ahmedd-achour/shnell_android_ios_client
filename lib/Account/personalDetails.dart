import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:shnell/AuthHandler.dart';

import 'package:shnell/dots.dart';
import 'package:shnell/functions.dart'; // Assumed MapTools import

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _showEditNameDialog(BuildContext context, String currentName) async {
    final TextEditingController controller = TextEditingController(text: currentName);
    String? errorMessage;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.all(20),
          title: Row(
            children: [
              const Icon(Icons.edit, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              const Text(
                'Edit Name',
                style: TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.amber.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.amber),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: errorMessage,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                ),
                onChanged: (value) {
                  if (value.trim().isEmpty) {
                    errorMessage = 'Name cannot be empty';
                  } else if (value.length > 50) {
                    errorMessage = 'Name must be 50 characters or less';
                  } else {
                    errorMessage = null;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name cannot be empty'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                if (controller.text.length > 50) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name must be 50 characters or less'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      setState(() {
        _isUpdating = true;
      });
      try {
        // Use Maptools if available, otherwise direct Firestore update
        await Maptools().updateFieldValue(
          collectionName: 'users',
          documentId: fb_auth.FirebaseAuth.instance.currentUser!.uid,
          fieldName: 'name',
          newValue: controller.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Name updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update name: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isUpdating = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthMethods authMethods = AuthMethods();
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final fb_auth.User? currentUser = authMethods.getCurrentUser();

    if (currentUser == null) {
      return Scaffold(
        body: const Center(
          child: RotatingDotsIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Info', style: TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.amber),
        elevation: 4,
      ),
      body: Stack(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: firestore.collection('users').doc(fb_auth.FirebaseAuth.instance.currentUser!.uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: RotatingDotsIndicator(),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
                );
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(
                  child: Text('User data not found.', style: TextStyle(color: Colors.white, fontSize: 16)),
                );
              }

              final userData = snapshot.data!.data() as Map<String, dynamic>;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildInfoTile(
                        context,
                        icon: Icons.person,
                        label: 'Name',
                        value: userData['name'] ?? 'Unknown',
                        isEditable: true,
                        onEdit: () => _showEditNameDialog(context, userData['name'] ?? ''),
                      ),
                    ),
                    const Divider(color: Colors.amber, thickness: 0.5),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildInfoTile(
                        context,
                        icon: Icons.email,
                        label: 'Email',
                        value: userData['email'] ?? 'Unknown',
                      ),
                    ),
                    const Divider(color: Colors.amber, thickness: 0.5),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildInfoTile(
                        context,
                        icon: Icons.phone,
                        label: 'Phone Number',
                        value: userData['phone'] ?? 'Unknown',
                      ),
                    ),
                    const Divider(color: Colors.amber, thickness: 0.5),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildInfoTile(
                        context,
                        icon: Icons.badge,
                        label: 'Role',
                        value: (userData['role'] as String?)?.toUpperCase() ?? 'Unknown',
                      ),
                    ),
                    if (userData['role'] == 'driver' && userData['vehicleType'] != null) ...[
                      const Divider(color: Colors.amber, thickness: 0.5),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildInfoTile(
                          context,
                          icon: Icons.directions_car,
                          label: 'Vehicle Type',
                          value: (userData['vehicleType'] as String?)?.toUpperCase() ?? 'Unknown',
                        ),
                      ),
                    ],
                    const Divider(color: Colors.amber, thickness: 0.5),
                  ],
                ),
              );
            },
          ),
          if (_isUpdating)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: RotatingDotsIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool isEditable = false,
    VoidCallback? onEdit,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.amber.shade50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.amber, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (isEditable)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.amber, size: 24),
                  onPressed: onEdit,
                  tooltip: 'Edit Name',
                ),
            ],
          ),
        ),
      ),
    );
  }
}