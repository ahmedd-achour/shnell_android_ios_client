import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/model/users.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Erreur d'authentification")),
      );
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n?.personalInformation ?? "Informations Personnelles",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(_currentUser!.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(l10n?.userDataNotFound ?? "Profil introuvable"),
            );
          }

          late shnellUsers user;
          try {
            user = shnellUsers.fromJson(
              snapshot.data!.data() as Map<String, dynamic>,
            );
          } catch (e) {
            return Center(child: Text("Erreur lecture profil: $e"));
          }

          return _buildContent(context, user);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, shnellUsers user) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(context, user),

            _buildSectionTitle(l10n?.accountInfo ?? "Compte", theme),
            _buildSettingsCard(
              children: [
                EditableInfoTile(
                  icon: Icons.person_outline,
                  label: l10n?.name ?? "Nom",
                  initialValue: user.name,
                  onSave: (val) async {
                    await _firestore
                        .collection('users')
                        .doc(_currentUser!.uid)
                        .update({'name': val});
                    await _currentUser!.updateDisplayName(val);
                  },
                  helperMessage: l10n?.updateNameHelper,
                ),
                _buildSeparator(),
                _buildReadOnlyTile(
                  icon: Icons.email_outlined,
                  label: l10n!.emailLabel,
                  value: user.email,
                  verified:
                      _currentUser!.emailVerified ||
                      _currentUser!.providerData
                          .any((p) => p.providerId == 'google.com'),
                ),
                _buildSeparator(),
                _buildReadOnlyTile(
                  icon: Icons.phone_outlined,
                  label: l10n.mobilePhoneLabel,
                  value: user.phone,
                ),
              ],
            ),


          ],
        ),
      ),
    );
  }

  /// ================= PROFILE HEADER =================
  Widget _buildProfileHeader(BuildContext context, shnellUsers user) {
    final theme = Theme.of(context);
    final authUser = FirebaseAuth.instance.currentUser;

    final photoUrl = authUser?.photoURL;
    final verified =
        authUser?.emailVerified == true ||
        authUser?.providerData.any((p) => p.providerId == 'google.com') == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? Icon(Icons.person,
                    size: 36, color: theme.colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (verified)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.verified,
                            size: 16, color: Colors.green),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ================= UI HELPERS =================
  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }

  Widget _buildSeparator() =>
      const Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16);

  Widget _buildReadOnlyTile({
    required IconData icon,
    required String label,
    required String value,
    bool verified = false,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (verified)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.verified,
                            size: 16, color: Colors.green),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// ================= EDITABLE TILE =================
class EditableInfoTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String initialValue;
  final Future<void> Function(String) onSave;
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  Future<void> _handleSave() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_controller.text.trim());
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(widget.icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: _isEditing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    onSubmitted: (_) => _handleSave(),
                    decoration: InputDecoration(
                      labelText: widget.label,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline)),
                      Text(
                        _controller.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
          if (_isSaving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: Icon(
                _isEditing ? Icons.check : Icons.edit,
                color:
                    _isEditing ? Colors.green : theme.colorScheme.primary,
              ),
              onPressed: () =>
                  _isEditing ? _handleSave() : setState(() => _isEditing = true),
            ),
        ],
      ),
    );
  }
}
