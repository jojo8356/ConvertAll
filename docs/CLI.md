# ConvertAll — interface en ligne de commande

- Version du document : 1.0 — 14 octobre 2026
- Concerne : ConvertAll 1.0.5 et suivants (`bin/convertall.dart`, `lib/cli/`)
- Voir aussi : [MCP.md](MCP.md) (serveur MCP pour un assistant IA)

`convertall` convertit une valeur entre deux unités, fouille la base d'unités
et décrit une unité, en texte ou en JSON. Il s'appuie sur **le même fichier de
données et les mêmes gestionnaires que l'application graphique et le serveur
MCP** : les trois répondent la même chose.

---

## 1. Installation et invocation

Depuis un dépôt prêt à l'emploi :

    $ flutter pub get
    $ dart run bin/convertall.dart convert 100 km/hr m/s
    100 km/hr = 27.77777778 m/s

Sous Windows, `dart` est `flutter_root\bin\dart.bat`. Pour ne plus préfixer :

    $ dart compile exe bin/convertall.dart -o convertall      # binaire natif
    $ sudo install -m755 convertall /usr/local/bin/           # sur le PATH

Le binaire compile embarque le code mais **pas** les données :
`assets/units.json` doit rester joignable (à côté du binaire, ou via
`--units-file` / `CONVERTALL_UNITS_FILE`, voir §6). L'outil est en Dart pur
(paquets `args`, `decimal`, `eval_ex`) et n'importe jamais Flutter.

---

## 2. Syntaxe

### 2.1 La valeur

Un nombre (`12`, `-3.5`, `1e6`) ou un calcul (`1/8`, `3*4+1`, `(2+2)/3`). La
notation accepte le point décimal, l'exposant `e` et le signe moins Unicode.

### 2.2 Les unités

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
`km/hour`, jamais `km/h` ; de même `mi/hr`, `m/s`.

**Unités non linéaires.** `C`, `F`, `Celsius`, `Fahrenheit`, `gas mark`,
`liter per 100 km`, `Beaufort wind` et `screw size` ne se combinent pas : ils
se convertissent seuls, sans exposant ni autre unité (`convert 100 C F`). Une
tentative du type `C*2` est refusée avec l'explication.

Une unité inconnue est refusée avec des suggestions :

    $ convertall convert 1 metr m
    convertall: The unit "metr" in the from expression "metr" is not known (626 units are available).
      did you mean: metric ton, metre, metric horsepower?

---

## 3. Commandes

### 3.1 `convert VALUE FROM TO`

    $ convertall convert 100 km/hr m/s
    100 km/hr = 27.77777778 m/s

| Option | Effet |
| --- | --- |
| `-n`, `--notation` | `short` (défaut), `fixed`, `scientific`, `engineering` |
| `-d`, `--decimals` | nombre de décimales, 0 à 15 (défaut 8) |
| `--details` | ajoute les unités de base, le multiplicateur et la grandeur |

    $ convertall convert 100 C F
    100 C = 212 F

    $ convertall convert 1 mile m --notation fixed --decimals 0
    1 mile = 1609 m

    $ convertall convert 1 Btu J --details
    1 Btu = 1055.05585262 J
    Base units: Btu = kg * m^2 / s^2; J = kg * m^2 / s^2
    Multiplier: 1 Btu = 1055.05585262 J
    Quantity: energy -> energy

### 3.2 `units [QUERY]`

Liste ou cherche des unités, par ordre alphabétique. `QUERY` (facultatif)
cherche en début de mot : `cel` trouve *Celsius*, *Celsius degree* et
*degree Celsius*.

| Option | Effet |
| --- | --- |
| `-t`, `--type` | restreint à une quantité (`--type volume`) |
| `-m`, `--limit` | nombre maximum d'unités, 1 à 500 (défaut 25) |

    $ convertall units --type volume --limit 4
    NAME        TYPE    DETAILS
    barrel      volume
    bbl         volume  barrel
    board feet  volume
    board foot  volume

    $ convertall units cel
    NAME            TYPE         DETAILS
    Celsius         temperature  non-linear
    Celsius degree  temp. diff.
    degree Celsius  temperature  non-linear

La colonne `DETAILS` reprend le nom développé (`bbl` → *barrel*), la note de la
base (`mph` → *miles/hour*) et l'étiquette `non-linear` quand une équation ou
une table est nécessaire.

### 3.3 `types`

Liste les 52 quantités avec leur nombre d'unités :

    $ convertall types
    acceleration                      2
    angle                             19
    area                              19
    capacitance                       5
    charge                            5
    ...

### 3.4 `info UNIT`

Décrit une unité : quantité, équivalent, unités de base, multiplicateur,
équation éventuelle, unités compatibles.

| Option | Effet |
| --- | --- |
| `--compatible-limit` | nombre d'unités compatibles à lister, 0 à 500 (défaut 15) |

    $ convertall info C
    C (Celsius) — temperature, non-linear
    Defined as: K
    Base units: K (multiplier 1)
    Comment: non-linear
    Compatible with 20 units: C deg, Celsius, Celsius degree, deg C, deg F, deg K, deg R, degree Celsius, degree Fahrenheit, degree Kelvin, F, F deg, Fahrenheit, Fahrenheit degree, Gas mark

Les unités compatibles sont celles qui se réduisent aux mêmes unités de base :
les degrés Celsius et Fahrenheit y figurent, une différence de température
étant proportionnelle à une différence de kelvins.

### 3.5 `compatible UNIT`

Liste les unités convertibles avec `UNIT` : la réponse à « je peux convertir
des litres en quoi ? ».

| Option | Effet |
| --- | --- |
| `-m`, `--limit` | nombre maximum d'unités, 1 à 500 (défaut 50) |

    $ convertall compatible "light year"
    81 units measure the same thing as "light year" (length):
    NAME                     TYPE    DETAILS
    American Wire Gauge Dia  length  use -1, -2 for 00, 000; non-linear
    angstrom                 length
    astronomical unit        length
    ...

Une expression composée est acceptée, et le titre affiche alors les unités de
base : `convertall compatible km/hr` répond `7 units … (m / s)`.

### 3.6 `mcp`

Lance le serveur MCP sur stdin/stdout (voir [MCP.md](MCP.md)).

### 3.7 `version`

    $ convertall version
    convertall 1.0.5
    626 units in 52 quantities
    MCP protocol revisions: 2026-07-28, 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05

### 3.8 Options globales et aide

| Option | Effet |
| --- | --- |
| `-h`, `--help` | aide générale, ou aide d'une commande (`convertall convert --help`) |
| `--version` | numéro de version |
| `--json` | résultat en JSON sur **stdout** (erreurs comprises) |
| `-v`, `--verbose` | trace du protocole MCP sur stderr (commande `mcp`) |
| `-l`, `--language` | langue des noms de quantités : `en`, `fr`, `auto` |
| `--units-file` | chemin de `units.json` |

Les options communes valent avant ou après la commande
(`convertall --json convert …` et `convertall convert … --json` sont
équivalents) ; en cas de doublon, la valeur donnée après la commande gagne.

---

## 4. Sortie JSON

`--json` écrit un unique objet JSON sur stdout — exploitable directement par
`jq` ou un script — et **ne met rien sur stderr** en cas d'échec, pour ne pas
polluer la sortie. Les exemples ci-dessous sont reformatés pour la lisibilité ;
la sortie réelle tient sur une seule ligne.

Succès : `{"ok": true, …}` suivi des membres produits par l'outil
correspondant.

    $ convertall --json convert 100 km/hr m/s
    {"ok":true,"result":"27.77777778","value":27.77777777777778,
     "from":"km/hr","to":"m/s"}

    $ convertall --json units cel
    {"ok":true,"count":3,"units":[
      {"name":"Celsius","type":"temperature","type_display":"temperature",
       "equivalent":"K","non_linear":true,"base_unit":false,"comment":"non-linear"},
      {"name":"Celsius degree","type":"temp. diff.","type_display":"temp. diff.",
       "equivalent":"C deg","non_linear":false,"base_unit":false},
      {"name":"degree Celsius","type":"temperature","type_display":"temperature",
       "equivalent":"K","non_linear":true,"base_unit":false,"comment":"non-linear"}]}

    $ convertall --json types
    {"ok":true,"types":[{"type":"acceleration","type_display":"acceleration","count":2}, …]}

    $ convertall --json info C
    {"ok":true,"unit":"C","type":"temperature","type_display":"temperature",
     "equivalent":"K","factor":1.0,"base_units":"K","non_linear":true,"base_unit":false,
     "unabbrev":"Celsius","comment":"non-linear","from_equation":"x + 273.15",
     "to_equation":"x - 273.15","compatible_unit_count":20,
     "compatible_units":["C deg","Celsius","Celsius degree","deg C","deg F","deg K",
       "deg R","degree Celsius","degree Fahrenheit","degree Kelvin","F","F deg",
       "Fahrenheit","Fahrenheit degree","Gas mark"]}

    $ convertall --json compatible km/hr --limit 3
    {"ok":true,"unit":"km/hr","category":"m / s","count":7,"units":[
      {"name":"Beaufort wind","type":"velocity","type_display":"velocity",
       "equivalent":"m/s","non_linear":true,"base_unit":false,"comment":"wind speed, non-linear"},
      {"name":"knot","type":"velocity","type_display":"velocity",
       "equivalent":"nmi/hr","non_linear":false,"base_unit":false},
      {"name":"kph","type":"velocity","type_display":"velocity","equivalent":"km/hr",
       "non_linear":false,"base_unit":false,"unabbrev":"kilometers/hour"}]}

    $ convertall --json version
    {"ok":true,"name":"convertall","version":"1.0.5","units":626,"unit_types":52,
     "mcp_protocol_versions":["2026-07-28","2025-11-25","2025-06-18","2025-03-26","2024-11-05"]}

Notes sur la forme des données :

- `count` compte **toutes** les correspondances, `units` seulement celles
  renvoyées (bornées par `--limit`) ;
- les valeurs numériques sont des nombres JSON (`27.77777777777778`, `1.0`) et
  `result` la chaîne affichée ;
- les membres facultatifs (`unabbrev`, `comment`, `from_equation`, …) sont
  absents quand la base ne les a pas — jamais `null` ;
- `base_unit` vaut `true` pour les dix unités de base (`equiv: "!"`) ;
- `category` est la quantité pour une unité simple, les unités de base réduites
  (`m / s`) pour une expression composée.

Échec : `{"ok": false, "error": …}` complété de `error_code` et, pour une unité
inconnue, de `suggestions`.

    $ convertall --json convert 1 kg m
    {"ok":false,"error":"Cannot convert from \"kg\" (mass) to \"m\" (length): these units do not measure the same quantity.","error_code":"incompatible_units"}

    $ convertall --json convert 1 metr m
    {"ok":false,"error":"The unit \"metr\" in the from expression \"metr\" is not known (626 units are available).","error_code":"unknown_unit","suggestions":["metric ton","metre","metric horsepower"]}

`error_code` est l'un des codes du moteur : `malformed_value`, `unknown_unit`,
`invalid_unit_expression`, `incompatible_units`, `non_linear_unit`,
`out_of_range`, `circular_definition`.

**Codes de sortie** (utiles dans un script) :

| Code | Signification |
| --- | --- |
| `0` | succès (ou `--help`) |
| `1` | erreur d'usage : argument manquant, commande ou option inconnue |
| `2` | l'opération a échoué : unité inconnue, unités incompatibles, valeur illisible |
| `3` | panne : données d'unités illisibles ou introuvables |

En mode texte, les messages d'erreur partent sur **stderr** et le résultat sur
stdout : `convertall convert 1 kg m 2>/dev/null` n'affiche donc rien.

---

## 5. Localisation

Les noms de quantités (« length », « temp. diff. ») existent en anglais et en
français dans `assets/units_fr.json`. La langue se choisit par `-l` :

    $ convertall units --type length -l fr

`-l auto` suit `LC_ALL`, `LC_MESSAGES` puis `LANG` ; une langue inconnue
retombe sur l'anglais avec un avertissement. Les **noms d'unités utilisés dans
les conversions restent ceux de la base** (noms anglais et symboles), quelle
que soit la langue d'affichage : `liter`, `l`, `mile`, `km/hr` fonctionnent
toujours.

---

## 6. Où sont les données

Ordre de recherche de `units.json` :

1. `--units-file CHEMIN` ;
2. la variable d'environnement `CONVERTALL_UNITS_FILE` ;
3. `assets/units.json`, `../assets/units.json`, `data/units.json`,
   `share/convertall/units.json`, `convertall/assets/units.json`, relatifs au
   script, au binaire et au répertoire courant (et à leurs parents, jusqu'à
   quatre niveaux).

Si rien n'est trouvé, la liste des chemins essayés est affichée et le code de
sortie est `3`. Le fichier de traduction `units_fr.json` est cherché à côté du
fichier de données.

---

## 7. Exemples dans un script

    # Vérifier une conversion dans un test shell
    result=$(convertall --json convert 100 km/hr m/s | jq -r .result)
    [ "$result" = "27.77777778" ] || exit 1

    # Remplir un tableau de correspondances
    while read -r value from to; do
      convertall --json convert "$value" "$from" "$to" \
        | jq -r '"\(.from) -> \(.result) \(.to)"'
    done < conversions.txt

    # Aide-mémoire des unités de volume
    convertall --json units --type volume --limit 500 | jq -r '.units[].name'

    # Lister ce dans quoi on peut convertir une unité
    convertall --json compatible liter | jq -r '.units[].name'

---

## 8. Dépannage

| Symptôme | Cause et remède |
| --- | --- |
| `The unit "h" … is not known` sur `km/h` | *h* est le henry : écrivez `km/hr` ou `km/hour` |
| `The unit data file was not found` (code 3) | pointez `--units-file` vers `assets/units.json` |
| `these units do not measure the same quantity` | les deux unités ne mesurent pas la même chose : `convertall compatible FROM` donne la liste utilisable |
| `"C*2" combines a non-linear unit with something else` | convertissez l'unité non linéaire seule |
| Le résultat perd des décimales | augmentez `--decimals` (0 à 15) ou choisissez `--notation scientific` |
| `dart: command not found` | utilisez le `dart` livré avec Flutter, ou compilez le binaire (`dart compile exe`) |
