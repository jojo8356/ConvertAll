# ConvertAll — interface en ligne de commande

- Version du document : 2.0 — 14 octobre 2026
- Concerne : ConvertAll 1.0.6 et suivants (`bin/convertall.dart`, `lib/cli/`)
- Voir aussi : [MCP.md](MCP.md) (serveur MCP pour un assistant IA)

`convertall` convertit une valeur entre deux unités, fouille la base d'unités,
décrit une unité, valide le catalogue, et sert le protocole MCP. Son interface
est **calquée sur l'outil Python de référence du dépôt `ConvertAll-py`**
(`source/cmdline.py`) : mêmes options courtes et longues, mêmes messages, mêmes
codes de sortie, mêmes résultats au caractère près. Elle y ajoute les commandes
décrites dans le cahier des charges
(`doc/CLI_RUST_CAHIER_DES_CHARGES.md` du dépôt Python) : sous-commandes,
sortie JSON, validation du catalogue et un **système de journalisation
complet** (niveaux de sévérité, journal de fichier, format JSON).

L'arithmétique est **exacte** : les facteurs du fichier de données sont des
fractions décimales, lues et multipliées comme des rationnels, si bien que
`1 in = 2.54 cm` est exact — pas `2.5400000000000005`. Le calcul repasse en
virgule flottante uniquement là où le catalogue le demande (équations de
température, interpolation des gas marks), conformément à la spécification.

---

## 1. Installation et invocation

Depuis un dépôt prêt à l'emploi :

    $ flutter pub get
    $ dart run bin/convertall.dart 1 in cm
    1 in = 2.54 cm

Sous Windows, `dart` est `flutter_root\bin\dart.bat`. Pour ne plus préfixer :

    $ dart compile exe bin/convertall.dart -o convertall      # binaire natif
    $ sudo install -m755 convertall /usr/local/bin/           # sur le PATH

Le binaire compilé embarque le code mais **pas** les données :
`assets/units.json` doit rester joignable (à côté du binaire, ou via
`--units-file` / `CONVERTALL_UNITS_FILE`, voir §10). L'outil est en Dart pur
(paquets `args`, `decimal`, `eval_ex`, `rational`) et n'importe jamais Flutter.

Il existe un second point d'entrée, `bin/convertall_mcp.dart`, qui ne fait que
servir le protocole MCP (§6.9) ; `convertall mcp` fait exactement la même
chose.

---

## 2. Notation des arguments

### 2.1 Les trois formes acceptées

    convertall [options] VALEUR UNITÉ_DÉPART UNITÉ_ARRIVÉE     # forme historique
    convertall convert [options] VALEUR UNITÉ_DÉPART UNITÉ_ARRIVÉE
    convertall COMMANDE [options] [arguments]

La **forme historique** est celle de l'outil Python : la commande se fait
implicitement, la valeur et les deux unités sont les arguments positionnels, et
les options peuvent précéder ou suivre. `convertall 1 in cm` et
`convertall convert 1 in cm` sont équivalents.

Les options s'écrivent `--nom=valeur`, `--nom valeur`, `-x` ou `-x valeur`.
Les unités contenant des espaces doivent être **entre guillemets**, comme le
rappelle le message d'aide : `convertall 1 "nautical mile" m`.

### 2.2 Les options, avec leur abréviation

| Courte | Longue | Argument | Effet |
| --- | --- | --- | --- |
| `-d` | `--decimals` | `0`–`12` | nombre de décimales affichées (défaut 8) |
| `-n` | `--notation` | `short`, `fixed`, `scientific`, `engineering` | notation du résultat |
| `-f` | `--fixed-decimals` | — | notation fixe, zéros de fin conservés |
| `-s` | `--sci-notation` | — | notation scientifique |
| `-e` | `--eng-notation` | — | notation ingénierie (exposant multiple de 3) |
| `-q` | `--quiet` | — | aucune invite ; ne journalise que les erreurs |
| `-i` | `--interactive` | — | mode interactif (§7) |
| `-x` | `--details` | — | ajoute les unités de base, le multiplicateur et la grandeur |
| `-t` | `--test` | — | valide le catalogue d'unités et sort |
| | `--test-all` | — | valide tous les catalogues installés et sort |
| `-l` | `--language` | `en`, `fr`, `auto` | langue des noms de types |
| | `--units-file` | chemin | fichier de données à utiliser |
| | `--json` | — | sortie JSON (§5.2) |
| | `--python-compat` | — | calcule comme l'outil Python historique (flottants) |
| | `--log-level` | `trace`…`critical` | niveau de journalisation (§8) |
| | `--verbose` | — | `--log-level=debug` |
| | `--log-file` | chemin | recopie aussi les traces dans un fichier |
| | `--log-format` | `text`, `json` | format des traces |
| | `--runtime-info` | — | version et catalogue en JSON (équivalent de l'option Python) |
| `-v` | `--version` | — | version de l'application, puis sortie |
| `-h` | `--help` | — | aide, puis sortie |

Deux options en conflit sont départagées dans cet ordre : `-f`, puis `-s`,
puis `-e`, puis `-n`. `--verbose` l'emporte sur `--quiet`, et un
`--log-level` explicite l'emporte sur les deux.

### 2.3 `--` et les nombres négatifs

Un argument qui commence par `-` est une option ; pour convertir un nombre
négatif, séparez-le avec `--`, exactement comme avec l'outil Python :

    $ convertall -q -- -40 C F
    -40 C = -40 F

---

## 3. Les valeurs et les unités

### 3.1 La valeur

Un nombre (`12`, `-3.5`, `1e6`) ou un calcul (`1/8`, `3*4+1`, `(2+2)/3`,
`10^3`). L'expression est évaluée **exactement** quand c'est de l'arithmétique :
`1/8` vaut le rationnel 1/8, pas le flottant 0.125. Les formes que l'évaluateur
de l'application connaît mais pas le moteur exact (`sqrt(2)`, `pi`, `1 000`,
`1,5`) sont évaluées en flottant, comme avant. Un nom d'unité omis devant la
valeur vaut `1.0` : `convertall -q in cm` affiche `1.0 in = 2.54 cm`.

### 3.2 Les unités

Les mêmes règles que dans l'application :

| Écriture | Sens |
| --- | --- |
| `km`, `Mile`, `FLUID OUNCE` | la casse est ignorée ; les espaces des noms composés sont acceptés |
| `m/s`, `km/hr`, `mi/hr` | division |
| `kg*m/s^2`, `N*m` | multiplication |
| `m^2`, `m2`, `s^-1` | exposants (`m2` et `m3` valent `m^2` et `m^3`) |
| `ft*lbf/hr`, `Btu/hr` | expressions composées |
| `1/s`, `1/mol` | inverse d'une unité |
| `(kg*m)/(s^2)` | parenthèses |

**Piège à connaître — les unités d'une lettre.** `h` est le **henry**
(inductance) et non l'heure, `l` est le litre, `C` le degré Celsius, `K` le
kelvin, `F` le degré Fahrenheit. Une vitesse s'écrit donc `km/hr` ou
`km/hour`, jamais `km/h` ; de même `mi/hr`.

**Unités non linéaires.** `C`, `F`, `Celsius`, `Fahrenheit`, `gas mark`,
`liter per 100 km`, `screw size` se convertissent **seules** : `C*m` ou `C^2`
sont refusés avec le code `non_linear_unit`.

### 3.3 Les suggestions

Un nom inconnu fait proposer les noms proches (début de mot, puis nom
contenant le texte) :

    $ convertall -q 1 metr m
    convertall: The unit "metr" in the from expression "metr" is not known (626 units are available).
      did you mean: metre, metric ton, metric horsepower?

---

## 4. Options de conversion en détail

    $ convertall -q -f -d 4 1 in cm
    1 in = 2.5400 cm
    $ convertall -q -s -d 3 1 km m
    1 km = 1.000E+03 m
    $ convertall -q -e -d 2 1 km m
    1 km = 1.00E+03 m
    $ convertall -q -d 4 1/8 cup ml
    1/8 cup = 29.57 ml
    $ convertall -q -f -d 4 1/8 cup ml
    1/8 cup = 29.5735 ml
    $ convertall -q -x 1 mile km
    1 mile = 1.609344 km
    Base units: mile = m; km = m
    Multiplier: 1 mile = 1.609344 km
    Quantity: length -> length

`-d` est le nombre de décimales pour `-f`, `-s` et `-e` (comme `%f` et `%E`
en Python), et le nombre de **chiffres significatifs** pour la notation par
défaut `short` (celle de `%G`) : `-d 4` donne `29.57` là où `-f -d 4` donne
`29.5735`. La borne haute est 12, comme `maxDecPlcs` dans l'implémentation
Python ; au-delà, le message est celui de l'outil Python :

    $ convertall -q -d 13 1 m cm
    Decimals must be an integer from 0 to 12.

---

## 5. Sorties

### 5.1 Texte (défaut)

Une ligne, exactement comme l'outil Python :

    VALEUR UNITÉ_DÉPART = RÉSULTAT UNITÉ_ARRIVÉE

Les **résultats** vont sur `stdout`, les **messages** (erreurs, suggestions,
traces) sur `stderr`. Un script peut donc lire `stdout` sans filtrage.

### 5.2 JSON

`--json` écrit un objet unique sur `stdout`. Le schéma est versionné
(`schema_version`), les clés sont en `snake_case`, et l'exactitude est
préservée : `value_exact` et `factor_exact` donnent la valeur exacte sous
forme décimale, ou de fraction (`5/9`) quand le décimal ne s'arrête pas.

    $ convertall --json 1 in cm
    {
      "schema_version": 1,
      "ok": true,
      "result": "2.54",
      "value": 2.54,
      "value_exact": "2.54",
      "as_fraction": "127/50",
      "exact": true,
      "from": "in",
      "to": "cm",
      "from_reduced": "m",
      "to_reduced": "m",
      "factor": 2.54,
      "factor_exact": "127/50",
      "from_category": "length",
      "to_category": "length",
      "notation": "short",
      "decimals": 8,
      "catalog": {"file": "assets/units.json", "sha256": "…", "units": 626},
      "tool": {"name": "convertall", "version": "1.0.6"}
    }

| Clé | Sens |
| --- | --- |
| `schema_version` | version du schéma JSON (1) |
| `ok` | vrai si l'opération a réussi |
| `result` | résultat mis en forme, tel qu'affiché en texte |
| `value` | valeur numérique (flottant) |
| `value_exact` | valeur exacte en texte (`2.54`, ou `5/9`) — absente si le calcul passe par une équation |
| `as_fraction` | valeur exacte en fraction réduite (`127/50`) — absente dans le même cas |
| `exact` | vrai quand la conversion n'a utilisé que des unités linéaires |
| `factor`, `factor_exact` | multiplicateur de l'unité de départ vers l'unité d'arrivée (`2.54` pour `in` → `cm`) ; `null` si une unité est non linéaire |
| `from_reduced`, `to_reduced` | unités de base des deux expressions |
| `from_category`, `to_category` | grandeur mesurée |
| `catalog` | fichier utilisé, SHA-256 et nombre d'unités — de quoi savoir **ce qui** a répondu |
| `tool` | nom et version de l'outil |

En cas d'échec, `--json` écrit aussi sur `stdout` :

    {"schema_version": 1, "ok": false, "error": "The unit \"metr\" …",
     "error_code": "unknown_unit", "exit_status": 1,
     "suggestions": ["metre", "metric ton", "metric horsepower"],
     "tool": {"name": "convertall", "version": "1.0.6"}}

Le code de sortie reste celui du texte (§11).

---

## 6. Les commandes

### 6.1 `convert`

    convertall convert 100 km/hr m/s
    convertall convert 70 F C -x

C'est la commande par défaut : l'écrire ou non revient au même.

### 6.2 `units`

    convertall units [RECHERCHE] [--type TYPE] [--limit N] [--sort name|type]

Fouille la base : `cel` trouve Celsius, `--type volume` restreint à une
grandeur, `--limit` borne la liste (défaut 25). La table est alignée.

### 6.3 `types`

Liste les grandeurs et leur nombre d'unités ; `--count` n'affiche que le
nombre.

### 6.4 `info`

    convertall info cal

Décrit une unité : type, équivalent, facteur (exact), unités de base,
équation ou table si elle est non linéaire, et unités compatibles
(`--compatible-limit`). C'est la commande à utiliser quand un nom est ambigu
(`ton`, `ounce`, `cal`).

### 6.5 `compatible`

    convertall compatible "light year"

Liste les unités convertibles avec celle-ci ; répond à « je peux convertir ça
en quoi ? ». `--limit` borne la liste (défaut 50).

### 6.6 `check`, `-t`, `--test`, `--test-all`

Valide le catalogue, comme `unitDataTest` dans l'outil Python : chaque unité
est analysée, réduite aux unités de base, son facteur est vérifié (fini,
positif) et son équation est évaluée.

    $ convertall -t
    units.json: 626 units
    All units pass tests
    $ convertall check --all
    units.json: 626 units
    All units pass tests
    units_fr.json: 52 units
    All units pass tests

Un catalogue cassé imprime les messages regroupés, puis les unités touchées,
et sort avec le code **3** :

    Invalid conversion for "broken unit"
       Impacts:  broken unit

`--all` valide en plus chaque traduction `units_<langue>.json` (les clés
doivent être des grandeurs connues, et toutes les grandeurs doivent être
traduites). `check --json` décrit chaque catalogue dans un objet `catalogs`.

### 6.7 `doctor`, `--runtime-info`

Version de l'application et de Dart, plateforme, langue, notation, niveau de
journalisation, et **le catalogue réellement lu** (chemin, SHA-256, nombre
d'unités). `doctor --json` (ou `--runtime-info`) donne la même chose en JSON,
sans effet de bord : aucun fichier n'est écrit.

### 6.8 `repl` — voir §7.

### 6.9 `mcp`

Sert le protocole MCP sur `stdin`/`stdout`. Rien d'autre que des messages
JSON-RPC n'est écrit sur `stdout` ; les traces suivent `--log-level` et vont
sur `stderr`. Voir [MCP.md](MCP.md).

### 6.10 `version`, `help`

`version` affiche la version, le nombre d'unités et les révisions du protocole
MCP ; `-v`/`--version` n'affiche que la version, **sans lire le catalogue** (ce
qui le rend utilisable partout). `help` affiche l'aide générale, `help
convert` celle d'une commande, et `convert --help` est équivalent.

---

## 7. Mode interactif

`-i` ou `repl` ouvre la session de l'outil Python :

    $ convertall -i
    Enter from unit -> in
    Enter to unit -> cm
    1.0 in = 2.54 cm
    Enter number, [n]ew, [r]everse or [q]uit -> 2
    2 in = 5.08 cm
    Enter number, [n]ew, [r]everse or [q]uit -> r
    2 cm = 0.78740157 in
    Enter number, [n]ew, [r]everse or [q]uit -> q

- une **valeur** remplace le nombre et reconvertit ;
- `r` (ou `reverse`) échange l'unité de départ et l'unité d'arrivée ;
- `n` (ou `new`) redemande deux unités et repart de `1.0` ;
- `q`, une **ligne vide** ou la fin de l'entrée (`Ctrl-D`) sortent avec le
  code 0 ;
- une unité inconnue est signalée et redemandée.

Aucun historique n'est écrit sur disque. Si `stdin` n'est pas un terminal, le
mode interactif lit simplement les lignes fournies : il reste testable et
utilisable dans un tube.

---

## 8. Journalisation

L'outil Python n'avait aucune trace : rien à voir entre le message final et
l'échec. `convertall` a un système complet, inspiré de `logging` en Python
(niveaux et sévérités numériques) et de syslog (une *facilité* par module).

### 8.1 Les niveaux

| Niveau | Sévérité | Ce qu'il porte |
| --- | --- | --- |
| `trace` | 5 | la configuration analysée (chaque option retenue) |
| `debug` | 10 | le déroulement : catalogue lu, requête, facteurs, résultat, durée |
| `info` | 20 | les faits de vie : version, catalogue (SHA-256), réponse, mode interactif |
| `warning` | 30 | la réponse est donnée, mais pas exactement comme demandé (unité inconnue, unités incompatibles, repli de langue, facteur non exact) |
| `error` | 40 | l'opération échoue (catalogue illisible, lot en échec) |
| `critical` | 50 | le programme s'arrête (défaillance inattendue) |

### 8.2 Le choix du niveau

Ordre de décision, le premier gagnant : `--log-level=…`, puis `--verbose`
(`debug`), puis `--quiet` (`error`), puis les variables
`CONVERTALL_LOG_LEVEL` / `CVT_LOG_LEVEL`, puis `warning` par défaut. Un nom de
niveau inconnu n'est pas fatal : il est signalé et le choix automatique est
conservé.

### 8.3 Où vont les traces

Sur `stderr` (jamais sur `stdout`, qui porte le résultat), et **en plus** dans
le fichier de `--log-file` (ajout en fin de fichier, horodaté).
`--log-format=json` écrit un objet JSON par ligne (`time`, `level`,
`severity`, `logger`, `message`) pour une lecture par un outil.

    $ convertall --verbose 1 in cm
    1 in = 2.54 cm
    2026-10-14 09:31:07 DEBUG    cli: convertall 1.0.6 started with: --verbose 1 in cm
    2026-10-14 09:31:07 INFO     catalog: reading the unit data from assets/units.json
    2026-10-14 09:31:07 INFO     catalog: 626 units in 52 quantities loaded from assets/units.json
    …
    2026-10-14 09:31:07 DEBUG    engine: result 127/50 (exact)
    2026-10-14 09:31:07 INFO     cli: answer: 1 in = 2.54 cm

### 8.4 Les facilités (loggers)

| Nom | Contenu |
| --- | --- |
| `cli` | la ligne de commande elle-même (options, réponse, durée) |
| `catalog` | la lecture et l'indexation du fichier d'unités |
| `engine` | les conversions : expressions réduites, facteurs, résultats, refus |
| `units` | l'analyse des expressions et les équations non linéaires |
| `check` | la validation du catalogue |
| `repl` | le mode interactif |
| `mcp.server` | les échanges du protocole MCP |

Un refus (unité inconnue, unités incompatibles, valeur illisible) est
journalisé en `warning` et **en plus** écrit sur `stderr` : un script qui
utilise `--quiet` garde le message, et une exécution `--verbose` garde la
trace complète avec la cause.

---

## 9. Arithmétique exacte et « chiffres ronds »

Deux moteurs cohabitent, comme le demande la spécification :

| Situation | Moteur | Conséquence |
| --- | --- | --- |
| facteurs linéaires, puissances entières, conversions entre unités linéaires | **rationnels exacts** (`package:rational`, entiers `BigInt`) | `1 in = 2.54 cm` **exactement**, `1 mile = 1.609344 km`, `1/16 pound` = `1/16` |
| unités non linéaires (équations, interpolation) | **flottants** (`double`) | mêmes formules que le catalogue, mêmes résultats que l'application |
| affichage | arrondi du décimal exact, « demi au pair » (comme `decimal` en Python) | plus de résidu binaire dans le texte |

Les facteurs du fichier de données ne sont donc plus lus comme des `double` :
`1/16.0` devient la fraction exacte `1/16`, et `2.176434e-8` (écrit avec un
signe moins Unicode dans six entrées) la fraction décimale correspondante. Le
résultat est visible immédiatement :

    $ convertall -q 1 in cm            # exact : 2.54, pas 2.5400000000000005
    $ convertall -q 32 F C             # 32 F = 0 C  (le résidu 5.7e-14 est arrondi)
    $ convertall --json 1 mile km      # value_exact : 1.609344

### 9.1 `--python-compat`

L'implémentation historique (Python) calcule tout en `double` : elle accumule
donc les arrondis binaires et laisse des résidus (`32 F` → `5.68434188608E-14
C`). `--python-compat` reproduit ce comportement, bits compris, pour comparer
deux sorties ou reproduire un ancien résultat :

    $ convertall -q 32 F C
    32 F = 0 C
    $ convertall -q --python-compat 32 F C
    32 F = 5.6843419E-14 C

La même option existe côté MCP (`python_compat` de `convert_value`).

---

## 10. Langue et fichiers de données

- `--language en|fr|auto` : langue des **noms de types** (`units_fr.json`).
  `auto` (défaut) suit `LC_ALL`, `LC_MESSAGES` puis `LANG`. Une langue sans
  traduction est signalée en `warning` et l'anglais est utilisé.
- `--units-file CHEMIN` : fichier de données à utiliser.
- `CONVERTALL_UNITS_FILE` : la même chose par variable d'environnement.
- Sans indication, l'outil cherche `assets/units.json` à côté du script, du
  binaire, du répertoire courant et de leurs parents (pratique en dépôt), puis
  `data/units.json` et `share/convertall/units.json` (pratique après
  installation).

---

## 11. Codes de sortie et erreurs

| Code | Sens | Compatibilité |
| --- | --- | --- |
| `0` | succès | identique à l'outil Python |
| `1` | erreur de conversion ou de données (unité inconnue, unités incompatibles, valeur non finie, hors plage) | identique |
| `2` | erreur d'usage (option inconnue, argument manquant, décimales hors bornes) | identique |
| `3` | catalogue introuvable, illisible ou refusé par `check` | **ajout** de la spécification |
| `130` | interruption au clavier | identique |

Les messages reprennent ceux du Python quand ils existent :

    A valid from unit is required            (-q sans unité de départ)
    A valid to unit is required              (-q sans unité d'arrivée)
    Decimals must be an integer from 0 to 12.
    Error in unit data - <détail>            (catalogue illisible, code 3)

et, pour les erreurs d'unité, les messages de l'application accompagnés du code
machine (`unknown_unit`, `incompatible_units`, `invalid_unit_expression`,
`non_linear_unit`, `out_of_range`, `malformed_value`, `circular_definition`).

---

## 12. Notes et dépannage

- Pas de mode « lot » : l'outil Python n'en a pas, et une boucle de shell
  suffit (`for v in …; do convertall -q $v m cm; done`). `cat valeurs.txt |
  xargs -L1 convertall -q` fonctionne aussi. Le cahier des charges propose en
  plus `--tsv`, `--json-lines`, `--batch`, `--file`, `--continue-on-error`,
  `--jobs`, `--color`, `--no-config`, `--history-file` ou `--relative-to` :
  aucun n'existe dans l'outil Python, aucun n'est implémenté ici, et la sortie
  `--json` (une ligne par appel) couvre déjà le besoin d'un script.
- L'outil n'ouvre **jamais** de fenêtre et n'écrit aucun fichier de
  configuration : `--version`, `--help` et `doctor` sont sûrs partout.
- Les résultats sont identiques à ceux de l'application graphique ; une seule
  différence voulue : l'application affiche le résidu des équations
  (`32 F = 5.68434188608e-14 C`), la ligne de commande l'arrondit à `0` (sauf
  avec `--python-compat`).
- `h` est le henry : `km/h` mesure une inductance, `km/hr` une vitesse.
- « The unit data file was not found » : passez `--units-file`, ou lancez
  l'outil depuis la racine du dépôt.

---

## 13. Tests

    $ flutter test test/core/ test/mcp/ test/cli/

- `test/core/exact_math_test.dart` : arithmétique exacte, arrondis, les quatre
  notations comparées aux sorties de Python.
- `test/core/conversion_engine_test.dart` : conversions, refus, exactitude.
- `test/core/parity_test.dart` : comparaison avec le modèle de l'application
  graphique (626 unités, matrice de conversions).
- `test/core/logging_test.dart` : niveaux, filtrage, formats.
- `test/core/sha256_test.dart` : l'empreinte du catalogue (vecteurs FIPS).
- `test/cli/cli_test.dart` : la ligne de commande de bout en bout, sorties
  capturées en mémoire (notation Python, codes de sortie, JSON, traces, mode
  interactif).
- `test/mcp/mcp_server_test.dart` : le serveur MCP.
