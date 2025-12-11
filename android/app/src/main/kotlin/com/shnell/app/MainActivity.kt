package com.shnell.app

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Bundle
import android.util.Log

// L'importation de CallkitIncomingPlugin est volontairement retirée
// pour contourner l'erreur "Unresolved reference" lors de la compilation.

class MainActivity: FlutterActivity() {
    
    // S'assurer que le code de gestion est appelé à la création (lancement) de l'Activity
    override fun onCreate(savedInstanceState: Bundle?) {
        // Appeler la méthode parente avant tout
        super.onCreate(savedInstanceState) 
        // Appeler le gestionnaire d'intent avec l'intent initial
        handleCallkitIntent(intent)
    }

    // S'assurer que le code de gestion est appelé si l'Activity est déjà en mémoire
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // L'Activity est lancée avec un nouvel Intent
        handleCallkitIntent(intent)
    }

    private fun handleCallkitIntent(intent: Intent?) {
        if (intent == null) return
        
        val action = intent.action
        
        // 🛑 CLÉ : Utiliser la chaîne de caractères littérale pour l'action ACCEPT
        // Le plugin Flutter Callkit est codé pour utiliser cette chaîne :
        val ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT" 
        
        if (action == ACTION_CALL_ACCEPT) {
            
            // Log pour confirmer que l'interception native a eu lieu
            Log.d("CallkitNative", "ACTION_CALL_ACCEPT détecté. Tentative de réveil du moteur Flutter.")
            
            // Le plugin Callkit gérera le reste du processus de transmission des données à Dart.
        } else if (action != Intent.ACTION_MAIN) {
            // Log pour les autres Intents (utile pour le débogage)
            Log.d("CallkitNative", "Intent reçu, non Callkit: $action")
        }
    }
}