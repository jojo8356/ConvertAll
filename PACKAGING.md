# ConvertAll — compilation et paquets Linux (Debian 12 x86_64)

Ce document donne les **commandes exactes** pour produire, sur
**Debian GNU/Linux 12 (bookworm) x86_64** :

1. un paquet **`.deb`**,
2. un **`.AppImage`**,
3. une **release** complète (archive `tar.gz`, paquets, publication GitHub).

Le paquet construit est **optimisé en taille** : rien n'est ajouté que
Flutter n'exige pas, et tout ce qui peut être retiré l'est (voir §4).

- Script de paquetage : `./ca_package.sh` (aucun droit root nécessaire sauf
  pour la commande `deps`).
- Script d'installation historique (binaire + script de lancement) :
  `./ca_make.sh install` — toujours valable, mais le `.deb` le remplace
  avantageusement.

---

## 0. Du clone au paquet (résumé)

```bash
# 1. Récupérer le projet et aller sur la branche de travail
git clone https://github.com/jojo8356/ConvertAll.git
cd ConvertAll
git checkout arena/2d99587e-convertall

# 2. Dépendances système (une seule fois, demande le mot de passe sudo)
sudo ./ca_package.sh deps

# 3. Flutter + compilation (une seule fois : télécharge Flutter 3.41.4)
./ca_make.sh build

# 4. Tester le logiciel
export PATH="$PATH:$(pwd)/flutter/bin"
flutter analyze                     # contrôle statique
flutter run -d linux                # lancer l'application et l'essayer

# 5. Compiler l'exécutable et construire les paquets
./ca_package.sh all                 # bundle + .deb + AppImage
ls -lh dist/
sudo apt install ./dist/convertall_1.0.3-1_amd64.deb
convertall                          # lancer la version installée
```

Ce qui se vérifie à l'œil pendant l'étape 4 : une conversion composée
(`ft * lbf / hr` → `N * m / sec`), le bouton d'échange central, le tri et le
clic dans la table des unités, le filtre par type, le menu latéral (Réglages,
Bases, Fractions, Aide) et le basculement de thème dans Réglages.

« Convertir en exe » = étape 5 : `flutter build linux --release` produit
l'exécutable natif `build/linux/x64/release/bundle/convertall` (ELF x86_64).
Cet exécutable ne fonctionne **que accompagné de ses dossiers `lib/` et
`data/`** : pour un fichier installable ou portable, utilisez le `.deb` ou
l'AppImage produits par la même commande.

---

## 1. Prérequis (une seule fois)

Debian 12 x86_64, session graphique, ~6 Go d'espace libre, connexion Internet.

```bash
# Outils de compilation, de paquetage et bibliothèques de Flutter Linux.
sudo ./ca_package.sh deps
```

Cette commande installe : `binutils curl dpkg-dev file gzip xz-utils zip unzip`
(paquetage) et `clang cmake git libgtk-3-dev libglu1-mesa ninja-build pkgconf
libstdc++-12-dev liblzma-dev` (compilation Flutter).

Flutter n'est pas fourni par Debian : il est téléchargé **une fois** par

```bash
./ca_make.sh build        # télécharge Flutter 3.41.4 (stable) dans ./flutter
```

`ca_package.sh` réutilise ce dossier, ou un `flutter` déjà présent dans le
`PATH`, ou la variable `FLUTTER=/chemin/vers/flutter`.

Contrôle rapide de l'outillage :

```bash
flutter --version         # doit afficher 3.41.4 (stable)
dpkg-deb --version
```

## 2. Paquet `.deb`

```bash
./ca_package.sh deb
```

Produit `dist/convertall_<version>-<révision>_amd64.deb` (≈ 11–15 Mo). Ce
paquet installe l'application dans `/opt/convertall`, crée le lien
`/usr/bin/convertall`, la entrée de menu
`/usr/share/applications/convertall.desktop`, les icônes `hicolor`
(48 → 512 px) et les métadonnées AppStream
`/usr/share/metainfo/org.bellz.convertall.appdata.xml`.

Installation et test :

```bash
sudo apt install ./dist/convertall_1.0.3-1_amd64.deb
convertall                                   # lance l'application
dpkg -L convertall                           # liste des fichiers installés
sudo apt remove convertall                   # désinstallation
```

Réglages utiles :

```bash
PKG_REV=2 ./ca_package.sh deb                # révision de paquet
MAINTAINER="Nom <mail>" ./ca_package.sh deb  # champ Maintainer
./ca_package.sh deb --skip-build             # réutilise le bundle existant
./ca_package.sh deb --out /tmp/sortie        # autre dossier de sortie
```

Le `.deb` se construit **sans `fakeroot`** : `dpkg-deb --root-owner-group`
écrit les fichiers en `root:root`, et la compression `-Zxz -z9` (xz niveau 9)
donne le plus petit paquet possible.

## 3. `.AppImage`

```bash
./ca_package.sh appimage
```

Produit `dist/convertall-<version>-x86_64.AppImage` (≈ 12–16 Mo).

- `appimagetool` est téléchargé automatiquement dans `./tools`
  (release 1.9.1, x86_64) s'il n'est pas déjà dans le `PATH`. Pour en imposer
  un autre : `APPIMAGETOOL=/chemin/appimagetool ./ca_package.sh appimage`.
- Sur Debian 12 (pas de `libfuse2` par défaut), le script exporte
  `APPIMAGE_EXTRACT_AND_RUN=1` pour lancer `appimagetool` sans FUSE.
- L'image est compressée en **zstd niveau 22** (`--comp zstd
  --mksquashfs-opt -Xcompression-level 22`) : bien plus petit que le gzip
  par défaut, et toujours rapide à monter.
- `SOURCE_DATE_EPOCH` est fixé à la date du dernier commit : deux
  constructions du même commit donnent le même fichier.

Test :

```bash
chmod +x dist/convertall-1.0.3-x86_64.AppImage
./dist/convertall-1.0.3-x86_64.AppImage
# Sans FUSE (Debian 12 de base) :
APPIMAGE_EXTRACT_AND_RUN=1 ./dist/convertall-1.0.3-x86_64.AppImage
```

## 4. Ce qui réduit la taille du paquet

Références : « Reducing app size » et « Obfuscate Dart code » de la
documentation Flutter (`docs.flutter.dev/perf/app-size`,
`docs.flutter.dev/deployment/obfuscate`).

| Mesure | Commande / réglage | Effet |
|---|---|---|
| Compilation AOT en mode release | `flutter build linux --release` | pas de VM Dart, pas d'assertions, code mort éliminé par compilation « tree shaking » |
| Icônes inutilisées supprimées | `uses-material-design: true` + `--tree-shake-icons` (activé par défaut en release) | seule la police d'icônes réellement utilisée est incluse |
| Informations de débogage hors du paquet | `--split-debug-info=build/symbols` | retire la table de symboles de `libapp.so` (le dossier `build/symbols` sert à symboliser les rapports de plantage) |
| Obfuscation (optionnel) | `./ca_package.sh all --obfuscate` | noms symboliques raccourcis, quelques centaines de Ko de plus gagnés |
| `strip` des binaires | automatique dans `ca_package.sh` | supprime les symboles du moteur Flutter et des greffons |
| Compression maximale du `.deb` | `dpkg-deb -Zxz -z9` | le plus petit format de paquet Debian courant |
| Compression AppImage | squashfs + zstd 22 | ≈ 40 % de moins qu'un AppImage gzip par défaut |
| Aucune police embarquée | police système (Roboto/DejaVu) | 0 Ko d'actif, et `--tree-shake-icons` reste efficace |
| Aucun actif superflu | `pubspec.yaml` ne liste que `units.json`, l'icône 48 px et `assets/help/` | les visuels de magasin (512/1024 px, dossier `assets/launcher/`) restent hors du bundle |
| Code spécifique à une plateforme | `kIsWeb` / `Platform.isWindows` … | le compilateur retire le code inatteignable pour Linux |

Vérifier la composition d'un bundle :

```bash
du -sh build/linux/x64/release/bundle
ls -lh build/linux/x64/release/bundle/lib/
flutter build linux --release --analyze-size   # rapport de taille détaillé
```

Ordre de grandeur attendu sur Debian 12 x86_64 (à titre indicatif) :

| Élément | Taille |
|---|---|
| `convertall` (embarqué du code C++ du projet) | ~ 15 Ko |
| `lib/libflutter_linux_gtk.so` | ~ 8 Mo (≈ 6 Mo après `strip`) |
| `lib/libapp.so` (code Dart AOT + actifs) | ~ 7 Mo (≈ 5 Mo sans symboles) |
| `data/icudtl.dat` | ~ 10 Mo (données de localisation ICU) |
| `data/flutter_assets/` | ~ 200 Ko |
| **`.deb` final** | **~ 11–15 Mo** |

## 5. Tout construire d'un coup

```bash
./ca_package.sh all                  # bundle + .deb + AppImage
./ca_package.sh all --obfuscate      # idem, avec obfuscation du code Dart
./ca_package.sh bundle               # seulement le bundle optimisé
```

## 6. Procédure de release

À exécuter sur la machine Debian 12 x86_64, dans l'ordre.

```bash
# 1. Version : bump dans pubspec.yaml (la version du .deb et de l'AppImage
#    en découle), puis journal des modifications.
#    version: 1.0.4+5
$EDITOR pubspec.yaml CHANGELOG.md DESIGN.md

# 2. Vérifications de base
flutter analyze                # le projet n'a pas encore de tests unitaires

# 3. Construction des paquets
./ca_package.sh all

# 4. Archive des sources
git archive --format=tar.gz --prefix=convertall-1.0.4/ \
    -o dist/convertall_1.0.4.tar.gz HEAD

# 5. Empreintes des fichiers (à joindre à la release)
( cd dist && sha256sum * > SHA256SUMS.txt && cat SHA256SUMS.txt )

# 6. Commit, tag et publication
git add -A && git commit -m "Release 1.0.4"
git tag -a v1.0.4 -m "Release 1.0.4"
git push origin master --follow-tags

gh release create v1.0.4 \
    --title "Production Release 1.0.4" \
    --notes-file CHANGELOG.md \
    dist/convertall_1.0.4-1_amd64.deb \
    dist/convertall-1.0.4-x86_64.AppImage \
    dist/convertall_1.0.4.tar.gz \
    dist/SHA256SUMS.txt
```

Commandes utiles ensuite :

```bash
gh release view v1.0.4                       # vérifier les fichiers publiés
gh release upload v1.0.4 dist/*.deb --clobber # remplacer un fichier
gh release delete v1.0.4                     # supprimer une release (brouillon)
```

Remarques :

- Le paquet `.deb` et l'AppImage n'existent que pour **x86_64** : `arm64` et
  `i686` demandent une machine (ou une compilation croisée) par
  architecture ; `ca_package.sh` refuse de produire un paquet étiqueté
  `amd64` sur une autre architecture.
- Les symboles de `build/symbols/` (et les fichiers `app.*.symbols` en cas
  d'obfuscation) **ne sont pas publiés** : ils servent à relire une pile
  d'appels (`flutter symbolize`).
- La version des métadonnées AppStream est générée automatiquement à partir
  de `pubspec.yaml` : ne pas la modifier à la main.
- Après publication, penser à mettre à jour `docs/download.html` (liens et
  tailles de fichiers) comme pour la release 1.0.3.
