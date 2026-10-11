---
# Configuration requise
---

## Web

ConvertAll fonctionne en ligne, sans installation. Voir
<http://convertall-web.bellz.org> pour l'essayer.

---

## Android

ConvertAll doit fonctionner sur Android 4.1 (Jelly Bean) et versions
ultérieures.

---

## Linux

ConvertAll doit fonctionner sur toute distribution Linux 64 bits. Les
plateformes 32 bits ne sont pas prises en charge.

Les dépendances suivantes sont nécessaires pour compiler et exécuter
ConvertAll, mais le script d'installation les installe automatiquement avec le
système de paquets natif :
* Clang
* CMake
* curl
* git
* en-têtes de développement GTK
* bibliothèque Mesa OpenGL
* Ninja
* pkg-config
* en-têtes de développement C++ standard
* unzip
* en-têtes de développement XZ
* utilitaires XZ
* zip

Le paquet Debian fourni installe, lui, ces dépendances comme dépendances du
système (`libgtk-3-0`, `libglib2.0-0`, `libstdc++6`, etc.) : elles ne sont pas
embarquées dans le paquet.

---

## Windows

ConvertAll doit fonctionner sur Windows 10 et versions ultérieures, en 64 bits.
Les plateformes 32 bits ne sont pas prises en charge.

---

## macOS

Faute de Macs pour les tests, ConvertAll n'est pas pris en charge sur macOS.
Toute aide pour créer un portage Mac serait appréciée.

---

## iOS

Faute de matériel pour le développement et les tests, ConvertAll n'est pas pris
en charge sur iOS. Toute aide pour créer un portage iOS serait appréciée.
