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
      return const Scaffold(body: Center(child: Text("Erreur d'authentification")));
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
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)
        ),
        centerTitle: true,
      ),
      // 1. STREAM UTILISATEUR
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(_currentUser!.uid).snapshots(),
        builder: (context, userSnapshot) {
          
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator());
          }
          
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return Center(child: Text(l10n?.userDataNotFound ?? "Profil introuvable"));
          }

          shnellUsers? userData;
          try {
            userData = shnellUsers.fromJson(userSnapshot.data!.data() as Map<String, dynamic>);
          } catch (e) {
            return Center(child: Text("Erreur lecture profil: $e"));
          }

          // Vérifier si l'utilisateur a un véhicule lié
       
          
          return _buildContent(context, userData);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, shnellUsers user) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- INFO COMPTE ---
            _buildSectionTitle(l10n?.accountInfo ?? "Compte", theme),
            _buildSettingsCard(
              children: [
                EditableInfoTile(
                  icon: Icons.person_outline,
                  label: l10n?.name ?? "Nom",
                  initialValue: user.name,
                  onSave: (val) async {
                    await _firestore.collection('users').doc(_currentUser!.uid).update({'name': val});
                    await _currentUser!.updateDisplayName(val);
                  },
                  helperMessage: l10n?.updateNameHelper,
                ),
                _buildSeparator(),
                _buildReadOnlyTile(icon: Icons.email_outlined, label: l10n!.emailLabel, value: user.email),
                _buildSeparator(),
                _buildReadOnlyTile(icon: Icons.phone_outlined, label: l10n.mobilePhoneLabel, value: user.phone),
              ],
            ),

            const SizedBox(height: 32),

            // --- SÉCURITÉ ---
            _buildSectionTitle(l10n.security, theme),
            _buildSettingsCard(
              children: [
                _buildSettingsTile(
                  icon: Icons.lock_outline,
                  title: l10n.changePassword,
                  onTap: () async {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.passwordResetSent), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
                      }
                    }
                  },
                  helperMessage: l10n.changePasswordHelper,
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }


  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
      child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }

  Widget _buildSeparator() => const Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16);

  Widget _buildReadOnlyTile({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  Widget _buildSettingsTile({required IconData icon, required String title, required VoidCallback onTap, String? helperMessage}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (helperMessage != null) Text(helperMessage, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ])),
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ]),
      ),
    );
  }
}

// --- WIDGET EDITABLE (Réutilisé) ---
class EditableInfoTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String initialValue;
  final Future<void> Function(String) onSave;
  final String? helperMessage;

  const EditableInfoTile({super.key, required this.icon, required this.label, required this.initialValue, required this.onSave, this.helperMessage});

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
      if (mounted) setState(() { _isEditing = false; _isSaving = false; });
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(children: [
        Icon(widget.icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: _isEditing
              ? TextField(controller: _controller, autofocus: true, onSubmitted: (_) => _handleSave(), decoration: InputDecoration(labelText: widget.label, isDense: true, border: const OutlineInputBorder()))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.label, style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                  Text(_controller.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
        ),
        if (_isSaving) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else IconButton(
          icon: Icon(_isEditing ? Icons.check : Icons.edit, color: _isEditing ? Colors.green : theme.colorScheme.primary),
          onPressed: () => _isEditing ? _handleSave() : setState(() => _isEditing = true),
        )
      ]),
    );
  }
}