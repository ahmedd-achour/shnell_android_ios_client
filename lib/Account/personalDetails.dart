import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/AuthHandler.dart';
import 'package:shnell/model/users.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  late final CollectionReference usersCollection;

  @override
  void initState() {
    super.initState();
    usersCollection = FirebaseFirestore.instance.collection('users');
  }

  @override
  Widget build(BuildContext context) {
    // Access theme once to reuse
    final theme = Theme.of(context);
    
    return Scaffold(
     body: StreamBuilder<DocumentSnapshot>(
        stream: usersCollection
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('User data not found.', style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          final userData = shnellUsers.fromJson(
              snapshot.data!.data() as Map<String, dynamic>);

          // Responsive Wrapper: Centers content and limits width on large screens
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle("Account Info"),
                      _buildSettingsCard(
                        context,
                        children: [
                          // Editable Name
                          // Key ensures widget rebuilds if DB updates remotely
                          EditableInfoTile(
                            key: ValueKey(userData.name), 
                            icon: Icons.person_outline,
                            label: "Name",
                            initialValue: userData.name,
                            onSave: (val) => AuthMethods.updateName(val),
                            helperMessage:
                                "Update your display name. This helps couriers and clients recognize you.",
                          ),
                          _buildSeparator(context),
                          // Read-only Email
                          _buildReadOnlyTile(
                            context: context,
                            icon: Icons.email_outlined,
                            label: "Email",
                            value: userData.email,
                          ),
                          _buildSeparator(context),
                          // Read-only Phone
                          _buildReadOnlyTile(
                            context: context,
                            icon: Icons.phone_outlined,
                            label: "Phone",
                            value: userData.phone,
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      _buildSectionTitle("Security"),
                      _buildSettingsCard(
                        context,
                        children: [
                          _buildSettingsTile(
                            context,
                            Icons.lock_outline,
                            "Change Password",
                            () {
                              AuthMethods.sendPasswordResetEmail();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'Password reset email has been sent.'),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                            helperMessage:
                                "You will receive a password reset email to update your password securely.",
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context,
      {required List<Widget> children}) {
    return Card(
      elevation: 2, // Slightly reduced elevation for a cleaner look
      clipBehavior: Clip.antiAlias, // Ensures InkWell ripples are clipped
      color: Theme.of(context).colorScheme.surfaceContainerLow, // M3 Card color
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).dividerColor.withOpacity(0.5),
    );
  }

  Widget _buildSettingsTile(
      BuildContext context, IconData icon, String title, VoidCallback onTap,
      {String? helperMessage}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (helperMessage != null)
          Padding(
            padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 16.0),
            child: Text(
              helperMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildReadOnlyTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? "Not provided" : value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // Optional: Add a lock icon to visually indicate read-only
          Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.outline.withOpacity(0.5)),
        ],
      ),
    );
  }
}

/// Editable field with pen icon
class EditableInfoTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String initialValue;
  final Function(String) onSave;
  final String? helperMessage;

  const EditableInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.initialValue,
    required this.onSave,
    this.helperMessage,
  });

  @override
  State<EditableInfoTile> createState() => _EditableInfoTileState();
}

class _EditableInfoTileState extends State<EditableInfoTile> {
  late TextEditingController _controller;
  bool _isEditing = false;
  bool _isLoading = false; // Add loading state for save action

  @override
  void initState() {
    _controller = TextEditingController(text: widget.initialValue);
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final value = _controller.text.trim();
    
    // Don't save if value hasn't changed
    if (value == widget.initialValue) {
       setState(() => _isEditing = false);
       return;
    }

    if (value.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await widget.onSave(value);
        if (mounted) {
           setState(() {
             _isEditing = false;
             _isLoading = false;
           });
           if (widget.helperMessage != null) {
              // Optional: Show success snackbar
           }
        }
      } catch (e) {
        if(mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating profile: $e'), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(widget.icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: _isEditing
                ? TextField(
                    controller: _controller,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: widget.label,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                      ),
                    ),
                    autofocus: true,
                    onSubmitted: (_) => _handleSave(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _controller.text,
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          _isLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: Icon(
                  _isEditing ? Icons.check_circle : Icons.edit,
                  color: _isEditing
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  size: _isEditing ? 28 : 24,
                ),
                onPressed: () {
                  if (_isEditing) {
                    _handleSave();
                  } else {
                    setState(() => _isEditing = true);
                  }
                },
              ),
        ],
      ),
    );
  }
}