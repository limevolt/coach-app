# Mon propre coach (Ollama sur le Mac)

Option facultative : l'app envoie ton suivi à ton propre modèle au lieu de passer par Claude.
Tout reste chez toi : iPhone → ton Mac → iPhone.

## 1. Installer Ollama sur le Mac (M1, 16 Go)

1. Télécharge Ollama sur https://ollama.com et installe-le.
2. Ouvre le Terminal et tape :
   ```
   ollama pull qwen3:8b
   ```
   (environ 5 Go). Alternatives : `llama3.1:8b`, `mistral-nemo`. Évite les modèles de plus de 14B avec 16 Go.
3. Autorise les connexions depuis l'iPhone (par défaut, Ollama n'écoute que le Mac lui-même) :
   ```
   launchctl setenv OLLAMA_HOST "0.0.0.0"
   ```
   puis quitte Ollama (icône lama dans la barre des menus › Quit) et relance-le.
   À refaire après chaque redémarrage du Mac, ou active « Expose Ollama to the network » dans les réglages d'Ollama si ta version le propose.
4. Empêche la mise en veille quand tu veux utiliser le coach : Réglages Système › Écran de verrouillage
   (ou lance `caffeinate -s` dans un Terminal).

## 2. Joindre le Mac depuis partout : Tailscale (gratuit)

1. Installe Tailscale sur le Mac et sur l'iPhone, connecte-toi avec le même compte.
2. Dans l'app Tailscale du Mac, note son adresse (100.x.x.x).

⚠️ N'ouvre jamais le port 11434 sur ta box : Ollama n'a pas de mot de passe.

## 3. Régler l'app

Réglages › **Mon propre coach** :
- Active « Utiliser mon propre coach ».
- Adresse : `http://100.x.x.x:11434` (ou `http://nom-du-mac.local:11434` à la maison).
- Modèle : `qwen3:8b`.
- Touche « Tester la connexion ».
- La consigne est pré-remplie ; tu peux l'adapter.

Ensuite, onglet **Suivi** › « Envoyer à mon coach ». Garde l'app ouverte pendant la réponse
(quelques secondes à une minute sur un M1). Le plan proposé s'affiche, avec le mot du coach :
« Appliquer » ou « Refuser ».

## Autres serveurs

Tout serveur compatible OpenAI (`/v1/chat/completions`) fonctionne : LM Studio, Open WebUI,
ou plus tard l'API de Lumo. Renseigne alors la clé d'accès si le serveur en demande une.
