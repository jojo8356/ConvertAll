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
flutter analyze lib                 # contrôle statique (voir la note ci-dessous)
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

### Vérifier que votre commit est bien le dernier poussé

```bash
git status -sb                 # la ligne doit commencer par "##" sans "[ahead N]"
git fetch origin               # met à jour la vue du dépôt distant
git log --oneline origin/arena/2d99587e-convertall..HEAD   # vide = rien à pousser
git log --oneline HEAD..origin/arena/2d99587e-convertall   # vide = rien à récupérer

git rev-parse HEAD                                         # hash local complet
git ls-remote origin refs/heads/arena/2d99587e-convertall  # hash réellement sur GitHub
```

Les deux hash doivent être **identiques**. Sinon :

```bash
git push origin arena/2d99587e-convertall
```

Autres repères :

```bash
git log -1 --format='%h %ad %an %s' --date=iso   # dernier commit local en clair
gh api repos/jojo8356/ConvertAll/commits/arena/2d99587e-convertall \
    --jq '.[0].sha[0:7] + " " + .[0].commit.message'   # dernier commit sur GitHub
```

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

Cette commande lance aussi `flutter pub get`, qui génère
`lib/l10n/app_localizations.dart` à partir de `lib/l10n/app_en.arb` et
`app_fr.arb` (voir `l10n.yaml`). Ce fichier n'est pas versionné : il est
recréé à chaque `pub get` / compilation.

`ca_package.sh` réutilise ce dossier, ou un `flutter` déjà présent dans le
`PATH`, ou la variable `FLUTTER=/chemin/vers/flutter`.

Contrôle rapide de l'outillage :

```bash
flutter --version         # doit afficher 3.41.4 (stable)
dpkg-deb --version
```

> **Note — `flutter analyze` seul analyse aussi le SDK.** Le SDK Flutter vit
> dans `./flutter/`, donc `flutter analyze` sans argument analyse également
> `flutter/dev/**` (les applications d'exemple du SDK) et affiche des
> centaines d'erreurs qui ne concernent pas ConvertAll. Analysez uniquement
> le code de l'application :
>
> ```bash
> flutter analyze lib
> ```
>
> (`flutter pub get` doit avoir été lancé au moins une fois, puisque le
> fichier généré `lib/l10n/app_localizations.dart` fait partie de `lib/`.)

## 2. Paquet `.deb`

```bash
./ca_package.sh deb
```

Produit `dist/convertall_<version>-<révision>_amd64.deb` (≈ 11–15 Mo). Ce
paquet installe l'application dans `/opt/convertall`, crée le lien
`/usr/bin/convertall`, l'entrée de menu
`/usr/share/applications/org.bellz.convertall.desktop`, les icônes `hicolor`
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

### Bibliothèques : citées en `Depends`, jamais embarquées

Le paquet ne contient **aucune bibliothèque déjà fournie par Debian** : ni
GTK, ni GLib, ni la libc, ni quoi que ce soit d'autre des dépôts. Il les
**cite** dans son champ `Depends`, et c'est `apt` qui les installe depuis les
dépôts Debian. Deux conséquences : le paquet reste petit, et il ne peut pas
entrer en conflit avec la copie système d'une bibliothèque.

`ca_package.sh` applique deux règles pendant la construction :

1. **Une bibliothèque système trouvée dans le bundle n'est pas empaquetée.**
   Chaque `.so` du bundle est lu (`objdump -p`, entrée `SONAME`) : si un paquet
   Debian installé sur la machine fournit ce *soname*, le fichier est retiré du
   bundle et seul son paquet est cité. Le journal de construction l'affiche :
   `not packaged: libc.so.6 (libc.so.6) is provided by the 'libc6' package`.
2. **`Depends` est calculé depuis le bundle lui-même**, comme le fait
   `dh_shlibdeps` : pour chaque fichier ELF du bundle (l'exécutable, le moteur
   Flutter et les greffons), chaque entrée `NEEDED` est résolue
   (`ldconfig` ou les répertoires standards) puis attribuée à son paquet
   Debian (`dpkg-query -S`). Le résultat est fusionné avec la base
   `libc6, libglib2.0-0, libgtk-3-0, libstdc++6` (les noms Debian 12) puis
   trié et replié en lignes de 74 colonnes.

Garantie d'installabilité : chaque paquet détecté est vérifié avec
`apt-cache show` ; un paquet que les dépôts de la machine ne connaissent pas
est **écarté** (avec un avertissement) au lieu de rendre le `.deb`
ininstalable. La base `libc6, libglib2.0-0, libgtk-3-0, libstdc++6` est
toujours conservée.

Les bibliothèques du bundle (le moteur Flutter, `libapp.so`, les greffons
`*_plugin.so`) sont reconnues comme telles et **ne déclenchent aucun
avertissement** : elles voyagent avec l'application, aucun paquet Debian ne
les fournit. Un avertissement
`warning: <soname> (needed by <fichier>) is not provided by any Debian
package` signale au contraire une bibliothèque **extérieure** que le `.deb`
ne peut pas citer : le paquet serait incomplet sur une machine propre. Dans
ce cas, installez le paquet Debian correspondant sur la machine de
construction (la détection le trouvera à la prochaine construction) ou, s'il
n'existe pas dans les dépôts, ajoutez-le à la variable `BASE_DEPENDS` en tête
de `ca_package.sh`.

Deux garde-fous :

- Si la construction n'a pas lieu sur **Debian 12**, `Depends` se limite à la
  base (les noms détectés pourraient ne pas exister dans les dépôts Debian) ;
  le script le signale.
- `--keep-system-libs` embarque malgré tout les bibliothèques système du
  bundle, ce qu'il ne faut **pas** faire pour un paquet Debian (réservé à des
  essais ou à une distribution hors dépôts). À utiliser aussi si un bundle
  contenait volontairement une version **plus récente** qu'un paquet système
  d'une même bibliothèque : dans ce cas la version embarquée serait retirée et
  c'est celle du système qui serait utilisée.

Vérifications :

```bash
dpkg-deb -f dist/convertall_1.0.3-1_amd64.deb Depends       # dépendances citées
dpkg-deb -c dist/convertall_1.0.3-1_amd64.deb | grep lib/   # rien de système
dpkg-deb -I dist/convertall_1.0.3-1_amd64.deb               # champ par champ
apt install --dry-run ./dist/convertall_1.0.3-1_amd64.deb   # vérifie la résolution
ldd /opt/convertall/convertall                              # après installation
```

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
- Comme pour le `.deb`, les bibliothèques système ne sont **pas** embarquées
  (voir §2) : la machine d'accueil doit fournir la pile GTK
  (`libgtk-3-0`, `libglib2.0-0`, `libstdc++6`), ce que Debian 12 installe par
  défaut avec un bureau. Le `.deb` déclare ces dépendances, l'AppImage les
  suppose présentes.
- `SOURCE_DATE_EPOCH` est fixé à la date du dernier commit : deux
  constructions du même commit donnent le même fichier.
- Les métadonnées AppStream sont cohérentes avec l'identité de l'application :
  fichier de métadonnées `org.bellz.convertall.appdata.xml` (= identifiant du
  composant), entrée de menu `org.bellz.convertall.desktop` (= identifiant +
  `.desktop`) et `<launchable>` pointant sur ce fichier. `appimagetool`
  cherche les métadonnées sous le nom du fichier `.desktop` : les deux noms
  doivent donc rester alignés, c'est la raison de ce nom en domaine inversé.

À savoir sur les vérifications d'`appimagetool` :

| Message | Signification |
|---|---|
| `appstreamcli command is missing` | `appstreamcli` (paquet `appstream`) n'est pas installé : aucune validation des métadonnées n'est faite. Sans conséquence, `--no-appstream` permet également de couper la vérification |
| `desktop-file-validate command is missing` puis arrêt | le paquet `desktop-file-utils` est **obligatoire** pour `appimagetool` (il est dans `./ca_package.sh deps`) |
| `WARNING: AppStream upstream metadata is missing` | `appimagetool` ne trouve pas `usr/share/metainfo/<nom du .desktop>.appdata.xml`. Vérifier que le nom du `.desktop` est `org.bellz.convertall.desktop` |

Si vous installez `appstream` (donc `appstreamcli`), `appimagetool` active
alors la validation : elle échoue dès le moindre avertissement de style, ce
qui peut arrêter la construction. Dans ce cas, utilisez
`./ca_package.sh appimage --no-appstream`.

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
| Aucune bibliothèque système embarquée | bibliothèques fournies par Debian hors du paquet | le `.deb` ne contient que l'exécutable, le moteur Flutter, les greffons et les données ; GTK/GLib/libc sont installés par `apt` |
| Dépendances calculées depuis le bundle | `objdump` + `dpkg-query`, comme `dh_shlibdeps` | `Depends` reflète exactement ce que le binaire utilise, donc le paquet s'installe partout sans dépendance manquante ni superflue |
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
flutter analyze lib            # le projet n'a pas encore de tests unitaires

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

- Le champ `Depends` est régénéré à chaque construction : ne pas le modifier
  à la main dans le script, il vient du bundle lui-même (voir §2).
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
