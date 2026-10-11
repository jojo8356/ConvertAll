---
# Installation
---

## Web

ConvertAll fonctionne en ligne, sans installation. Voir
<http://convertall-web.bellz.org> pour l'essayer.

---

## Android

ConvertAll peut être installé depuis Google Play,
[ici](https://play.google.com/store/apps/details?id=org.bellz.convertall).

Un fichier APK (convertall_x.x.x.apk) est également fourni : il peut être
téléchargé sur un appareil Android et exécuté directement.

---

## Linux (Debian / Ubuntu)

Le plus simple est d'installer le paquet Debian fourni avec la version :

    $ sudo apt install ./convertall_x.x.x-y_amd64.deb

Pour une installation sans droits d'administrateur, utilisez l'AppImage, qui
tient dans un seul fichier :

    $ chmod +x convertall-x.x.x-x86_64.AppImage
    $ ./convertall-x.x.x-x86_64.AppImage

Pour compiler à partir des sources, extrayez les fichiers de l'archive
(convertall_x.x.x.tar.gz) dans un répertoire dont vous êtes propriétaire. Vous
avez besoin d'au moins 6 Go d'espace disque pour la compilation automatique.
Placez-vous ensuite dans le répertoire `ConvertAll` dans un terminal et lancez
les commandes suivantes :

    $ sudo ./ca_package.sh deps
    $ ./ca_make.sh build
    $ ./ca_package.sh all

La première commande installe les dépendances avec le système de paquets natif
(`apt-get`). La deuxième télécharge Flutter et compile ConvertAll. La troisième
produit le paquet `.deb` et l'AppImage dans le dossier `dist/`. Pour installer
la version compilée sans passer par un paquet :

    $ sudo ./ca_make.sh install

Après cette étape, le répertoire temporaire `ConvertAll` peut être supprimé.

---

## Windows

Le plus simple est de télécharger le fichier « convertall_x.x.x.zip » et d'en
extraire tout le contenu dans un dossier vide, puis d'exécuter
« convertall.exe ».

Pour compiler ConvertAll à partir des sources, récupérez celles-ci sur
<https://github.com/doug-101/ConvertAll>. Installez également Flutter en
suivant les instructions de
<https://docs.flutter.dev/get-started/install/linux>. La partie « Android
Setup » n'est pas nécessaire : seul le volet Linux en bas de page l'est.
