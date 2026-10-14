# ConvertAll — serveur MCP et interface en ligne de commande

- Version du document : 1.0 — 14 octobre 2026
- Concerne : ConvertAll 1.0.5 et suivants (`lib/core/`, `lib/cli/`, `lib/mcp/`,
  `bin/`)
- Référence de la ligne de commande : [CLI.md](CLI.md)

Ce document décrit **le protocole MCP (Model Context Protocol) tel qu'il est
implémenté dans ce dépôt** : le serveur `convertall mcp`, les cinq outils
exposés à un modèle de langage, la négociation de version, le format exact des
messages, la configuration des clients, l'architecture du code et les tests.
Il sert à la fois de mode d'emploi (brancher ConvertAll dans un assistant) et
de référence pour qui doit modifier l'implémentation.

---

## 1. En deux minutes

ConvertAll expose sa base d'unités (626 unités, 52 quantités) de trois façons :

| Point d'entrée | Commande | Usage |
| --- | --- | --- |
| Application graphique | `flutter run` | usage humain interactif (existant) |
| Ligne de commande | `dart run bin/convertall.dart convert 100 km/hr m/s` | scripts, terminal, `--json` |
| **Serveur MCP** | `dart run bin/convertall_mcp.dart` | assistants IA (Claude, Copilot, Cursor, ...) |

Le serveur MCP ne parle que sur **stdin/stdout** (une ligne JSON par message,
voir §8.8) et n'écrit **jamais** autre chose sur stdout : les traces vont sur
stderr. Il ne lit et n'écrit aucun fichier en dehors de `assets/units.json` et
n'accède à aucun réseau.

Les cinq outils exposés :

| Outil | Répond à |
| --- | --- |
| `convert_value` | « combien font 100 km/hr en m/s ? » |
| `list_unit_types` | « quelles grandeurs connais-tu ? » |
| `search_units` | « trouve-moi l'unité qui s'appelle *cel*… » |
| `get_unit_info` | « *cal*, c'est quoi exactement ? » |
| `find_compatible_units` | « je peux convertir des litres en quoi ? » |

Exemple de session (client → serveur, puis serveur → client) :

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"convert_value",
 "arguments":{"value":"100","from":"km/hr","to":"m/s"},
 "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",
          "io.modelcontextprotocol/clientCapabilities":{}}}}
```

```json
{"jsonrpc":"2.0","id":1,"result":{"content":[
  {"type":"text","text":"100 km/hr = 27.77777778 m/s"},
  {"type":"text","text":"{\"result\":\"27.77777778\",\"value\":27.77777777777778,\"from\":\"km/hr\",\"to\":\"m/s\"}"}],
  "structuredContent":{"result":"27.77777778","value":27.77777777777778,
                       "from":"km/hr","to":"m/s"},
  "resultType":"complete",
  "_meta":{"io.modelcontextprotocol/serverInfo":{"name":"convertall","version":"1.0.5","title":"ConvertAll unit conversion","description":"Unit conversion server backed by the unit database of the ConvertAll application.","websiteUrl":"http://convertall.bellz.org"}}}}
```

---

## 2. Qu'est-ce que MCP ?

Le **Model Context Protocol** est un protocole ouvert, en JSON-RPC 2.0, qui
permet à un assistant (le *client*) d'appeler des capacités exposées par un
programme local (le *serveur*). ConvertAll est ici le serveur : le modèle
demande une conversion, le serveur répond avec la valeur, une explication, et
des données structurées.

Deux notions gouvernent tout le reste, et cette implémentation les traite
toutes les deux :

### 2.1 Ère *legacy* — la poignée de main `initialize`

Les révisions **2024-11-05, 2025-03-26, 2025-06-18 et 2025-11-25** commencent
par une requête `initialize` (version, capacités, identité du client), à
laquelle le serveur répond par sa propre version, ses capacités et son
identité ; le client envoie ensuite `notifications/initialized`, puis les
requêtes utiles (`tools/list`, `tools/call`, `ping`, ...). C'est la forme que
comprennent aujourd'hui la plupart des clients installés.

### 2.2 Ère *modern* — les métadonnées par requête (révision 2026-07-28)

La révision **2026-07-28** supprime l'état de session : **chaque requête**
porte sa version de protocole et les capacités du client dans `params._meta`.
Plus de `initialize`, plus de `notifications/initialized`, plus de `ping`, et
chaque résultat est étiqueté par un champ `resultType`. En échange, un client
qui parle cette révision **doit** pouvoir appeler `server/discover` pour
apprendre qui est le serveur et quelles versions il accepte, puis citer les
indices de cache (`ttlMs`, `cacheScope`) renvoyés par les listes.

### 2.3 Serveur « bi-ère »

Un serveur peut servir les deux ères : c'est ce que fait
`lib/mcp/mcp_server.dart`. Un client moderne est détecté à la présence de
`_meta` et servi en sémantique nouvelle ; un client qui ouvre par `initialize`
bascule le processus en sémantique ancienne (résultats sans `resultType`, sans
indices de cache, `ping` accepté) pour le reste de la connexion. Le test
`test/mcp/mcp_server_test.dart` couvre les deux chemins.

---

## 3. Prérequis

- **Dart 3.8 ou plus** (le SDK embarqué dans Flutter convient) ;
- les dépendances pures Dart `args`, `decimal`, `eval_ex` (déjà déclarées dans
  `pubspec.yaml`) ;
- le fichier de données `assets/units.json`, livré avec le dépôt.

`bin/convertall.dart` et `bin/convertall_mcp.dart` **n'importent pas Flutter** :
ils compilent et s'exécutent avec le seul SDK Dart. Depuis un dépôt Flutter,
récupérez d'abord les dépendances :

    $ flutter pub get          # ou `dart pub get` avec un SDK Dart seul
    $ dart run bin/convertall_mcp.dart --help

### 3.1 Binaire autonome (recommandé pour un client IA)

Un binaire natif évite d'avoir à installer le SDK sur la machine et supprime
le coût de démarrage du JIT :

    $ dart compile exe bin/convertall_mcp.dart -o convertall-mcp
    $ cp assets/units.json .          # à placer à côté du binaire…
    $ ./convertall-mcp --units-file ./units.json --version

`dart compile exe bin/convertall.dart -o convertall` donne le même résultat
pour l'outil de ligne de commande (voir [CLI.md](CLI.md)).

---

## 4. Lancer le serveur

Deux entrées équivalentes :

    $ dart run bin/convertall_mcp.dart          # serveur seul
    $ dart run bin/convertall.dart mcp          # via la ligne de commande

Options communes :

| Option | Effet |
| --- | --- |
| `--units-file CHEMIN` | chemin de `units.json` (défaut : recherche automatique) |
| `-l`, `--language LANG` | langue des noms de quantités : `en` (défaut), `fr`, `auto` |
| `-v`, `--verbose` | trace chaque échange du protocole sur **stderr** |
| `--version` | affiche le numéro de version et sort |
| `-h`, `--help` | affiche l'aide et sort |

Recherche du fichier de données, dans l'ordre : `--units-file`, puis la
variable d'environnement `CONVERTALL_UNITS_FILE`, puis une liste d'emplacements
relatifs au script, au binaire et au répertoire courant (`assets/units.json`,
`../assets/units.json`, `data/units.json`, `share/convertall/units.json`,
`convertall/assets/units.json`, en remontant jusqu'à quatre niveaux de
répertoires parents). Voir `lib/cli/database_locator.dart`.

Codes de sortie du serveur :

| Code | Signification |
| --- | --- |
| `0` | fin normale : l'entrée standard a été fermée (arrêt demandé par le client) |
| `2` | erreur d'usage (option inconnue) |
| `3` | données d'unités illisibles ou introuvables |

---

## 5. Brancher un client IA

Tous les clients MCP se configurent de la même manière : **une commande** et
ses arguments. Remplacez `/chemin/vers/ConvertAll` par le chemin réel du
dépôt.

### 5.1 Claude Desktop

Fichier `claude_desktop_config.json` (menu *Settings → Developer → Edit
Config*), section `mcpServers` :

```json
{
  "mcpServers": {
    "convertall": {
      "command": "dart",
      "args": ["run", "/chemin/vers/ConvertAll/bin/convertall_mcp.dart"]
    }
  }
}
```

Variante binaire autonome (aucun SDK requis) :

```json
{
  "mcpServers": {
    "convertall": {
      "command": "/chemin/vers/convertall-mcp",
      "args": ["--units-file", "/chemin/vers/ConvertAll/assets/units.json"]
    }
  }
}
```

### 5.2 VS Code (GitHub Copilot, mode agent)

`.vscode/mcp.json` (ou *MCP: Add Server* dans la palette de commandes) :

```json
{
  "servers": {
    "convertall": {
      "type": "stdio",
      "command": "/chemin/vers/convertall-mcp",
      "args": ["--units-file", "/chemin/vers/ConvertAll/assets/units.json"]
    }
  }
}
```

### 5.3 Cursor / Cline / Windsurf et autres

Tous utilisent le même schéma `command` + `args` :

- Cursor : `~/.cursor/mcp.json`, clé `mcpServers` ;
- Cline : panneau MCP → *Configure MCP Servers*, clé `mcpServers` ;
- Windsurf : `~/.codeium/windsurf/mcp_config.json`, clé `mcpServers`.

### 5.4 Client sans support MCP

Un modèle ou un script qui ne parle pas MCP peut utiliser la ligne de commande
(`convertall convert … --json`) : la sortie JSON contient les mêmes données que
le `structuredContent` des outils. Voir [CLI.md](CLI.md).

### 5.5 Vérifier le branchement

    $ echo '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}' \
        | dart run bin/convertall_mcp.dart

La réponse doit contenir `"supportedVersions":["2026-07-28"]` et la liste des
capacités. Si la commande échoue avec le code 3, le chemin du fichier de
données est en cause : ajoutez `--units-file`.

---

## 6. Référence des outils

Chaque outil déclare un `inputSchema` **et** un `outputSchema` (JSON Schema
2020-12). Les arguments reçus sont validés contre `inputSchema` avant l'appel :
un argument manquant ou hors bornes est refusé par une erreur JSON-RPC
`-32602` dont le message nomme le membre fautif. Le résultat est disponible
deux fois : en texte (premier bloc `content`, c'est ce que lit le modèle) et en
JSON (`structuredContent`, conforme à `outputSchema`). Une conversion refusée
pour une raison métier n'est **pas** une erreur de protocole : l'outil répond
avec `isError: true`, un message explicatif et, si possible, des suggestions.

Tous les outils sont en lecture seule (`readOnlyHint: true`,
`idempotentHint: true`, `openWorldHint: false`, `destructiveHint: false`).

### 6.1 `convert_value`

> Convertit un nombre d'une unité à une autre.

Arguments :

| Nom | Type | Requis | Défaut | Description |
| --- | --- | --- | --- | --- |
| `value` | chaîne ou nombre | oui | — | nombre (« 12 », « -3.5 », « 1e6 ») ou calcul (« 1/8 », « 3*4+1 ») |
| `from` | chaîne | oui | — | unité de départ, simple ou composée |
| `to` | chaîne | oui | — | unité d'arrivée |
| `notation` | `short` \| `fixed` \| `scientific` \| `engineering` | non | `short` | écriture du résultat |
| `decimals` | entier 0–15 | non | `8` | nombre de décimales |
| `include_details` | booléen | non | `false` | ajoute unités de base, multiplicateur et grandeur |

Sortie : `result` (chaîne affichée), `value` (nombre), `from`, `to`, et si
`include_details` : `from_reduced`, `to_reduced`, `factor`, `from_category`,
`to_category`, `notation`, `decimals`.

```json
{"name":"convert_value","arguments":{"value":"60","from":"mi/hr","to":"km/hr"}}
```

```text
60 mi/hr = 96.56064 km/hr
```

```json
{"result":"96.56064","value":96.56063999999999,"from":"mi/hr","to":"km/hr"}
```

Cas d'erreur typiques (tous en `isError: true`, avec `error_code` dans le
second bloc texte) :

| Situation | `error_code` | Message |
| --- | --- | --- |
| unité inconnue | `unknown_unit` | `The unit "metr" in the from expression "metr" is not known (626 units are available).` + `suggestions: ["metric ton", "metre", "metric horsepower"]` |
| expressions de nature différente | `incompatible_units` | `Cannot convert from "kg" (mass) to "m" (length): these units do not measure the same quantity.` |
| unité non linéaire combinée | `non_linear_unit` | `"C*2" combines a non-linear unit with something else. …` |
| valeur illisible | `malformed_value` | `Cannot read "abc" as a number or a calculation.` |
| expression incomplète (`m/`) | `invalid_unit_expression` | `The from expression "m/" is incomplete: it ends with an operator…` |

**Piège à connaître :** `h` est le **henry** (inductance), pas l'heure ; une
vitesse s'écrit `km/hr` ou `km/hour`. De même `l` est le litre. Le champ
`instructions` et la description de l'outil le rappellent au modèle.

### 6.2 `list_unit_types`

Aucun argument. Renvoie les 52 quantités avec leur nombre d'unités :

```json
{"types":[{"type":"acceleration","type_display":"acceleration","count":2}, ...]}
```

### 6.3 `search_units`

| Nom | Type | Requis | Défaut | Description |
| --- | --- | --- | --- | --- |
| `query` | chaîne | non | `""` | texte cherché **au début d'un mot** du nom (`cel` → Celsius) |
| `type` | chaîne | non | — | restreint à une quantité (nom anglais ou affiché) |
| `limit` | entier 1–200 | non | `25` | nombre maximum d'unités renvoyées |

Sortie : `count` (nombre total de correspondances) et `units` (au plus `limit`
unités), dans l'ordre alphabétique. Si `query` est vide, toute la base est
listée : c'est le moyen de découvrir les noms exacts à utiliser ensuite dans
`convert_value`.

### 6.4 `get_unit_info`

| Nom | Type | Requis | Défaut | Description |
| --- | --- | --- | --- | --- |
| `unit` | chaîne | oui | — | nom d'unité (`cal`) |
| `compatible_limit` | entier 0–200 | non | `15` | nombre d'unités compatibles à inclure (`0` : aucune) |

Sortie : `unit`, `type`, `type_display`, `equivalent`, `factor`, `base_units`,
`non_linear`, `base_unit`, et selon les données `unabbrev`, `comment`,
`from_equation`, `to_equation`, `compatible_unit_count`, `compatible_units`.

Pour Celsius : `non_linear: true`, `from_equation: "x + 273.15"`,
`to_equation: "x - 273.15"`, `base_units: "K"`.

### 6.5 `find_compatible_units`

| Nom | Type | Requis | Défaut | Description |
| --- | --- | --- | --- | --- |
| `unit` | chaîne | oui | — | unité ou expression (`km/hr`) |
| `limit` | entier 1–500 | non | `50` | nombre maximum d'unités |

Sortie : `unit`, `category` (la quantité, ou les unités de base réduites pour
une expression composée : `m / s`), `count` et `units`. C'est l'outil à
appeler **avant** `convert_value` quand l'unité d'arrivée n'est pas certaine :
il évite l'échec « these units do not measure the same quantity ».

---

## 7. Ce qui n'est pas exposé

Le serveur déclare uniquement la capacité `tools` (`listChanged: false`). Les
méthodes non implémentées répondent une erreur JSON-RPC `-32601` (méthode
inconnue) dont le champ `data.supportedMethods` rappelle la liste utile —
notamment `resources/list`, `prompts/list`, `completion/complete`,
`subscriptions/listen` et `logging/setLevel`. Ce choix est délibéré :

- MCP distingue les outils (actions avec arguments) des ressources (données
  adressables par URI) et des invites (gabarits). Un convertisseur n'a rien à
  adresser par URI : les cinq outils couvrent le besoin, et une surface plus
  petite est une surface plus fiable pour un modèle ;
- exposer des ressources coûterait des listes paginées, des `subscribe` et des
  notifications de changement, sans valeur ajoutée ici.

Les notifications sont acceptées et ignorées sans réponse :
`notifications/cancelled` (les outils répondent en quelques millisecondes, il
n'y a rien à interrompre), `notifications/initialized` (fin de poignée de main
ancienne), et toute autre notification (`notifications/progress`,
`notifications/roots/list_changed`).

---

## 8. Le protocole, dans le détail

### 8.1 Méthodes servies

| Méthode | Ère | Rôle |
| --- | --- | --- |
| `server/discover` | modern | versions supportées, capacités, `instructions`, indices de cache |
| `tools/list` | les deux | les cinq outils avec leurs schémas et annotations |
| `tools/call` | les deux | exécution d'un outil |
| `initialize` | legacy | poignée de main, sélectionne l'ère ancienne |
| `ping` | legacy | réponse `{}` (supprimé par la révision 2026-07-28) |

### 8.2 Métadonnées obligatoires (ère modern)

Toute requête doit porter :

```json
"params": {"_meta": {
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientCapabilities": {},
  "io.modelcontextprotocol/clientInfo": {"name":"...","version":"..."}
}}
```

`protocolVersion` et `clientCapabilities` sont **exigés** ; `clientInfo` est
recommandé ; `logLevel` est accepté (voir §8.6). En l'absence de `_meta`, la
réponse est `-32602` avec un message qui explique qu'il s'agit d'une requête de
révision moderne et qu'un client plus ancien doit ouvrir par `initialize`. Une
version non supportée reçoit `-32022` (`UnsupportedProtocolVersion`) avec
`data: {"supported": ["2026-07-28"], "requested": "…"}`.

### 8.3 Négociation de version (ère legacy)

`initialize` avec `protocolVersion` ∈ {`2024-11-05`, `2025-03-26`,
`2025-06-18`, `2025-11-25`} → le serveur renvoie cette même version et
`capabilities: {"tools": {"listChanged": false}}`, `serverInfo` et
`instructions`. Toute autre valeur → le serveur répond avec
`2025-11-25` (sa version ancienne la plus récente), comme la spécification
l'autorise, et poursuit en mode ancien.

### 8.4 Forme des résultats

Ère modern — tout résultat porte `resultType: "complete"` (le serveur ne
produit jamais `input_required` : aucun de ses outils n'a besoin d'un aller
retour supplémentaire) et, en `_meta`, la fiche `serverInfo` :

```json
{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","content":[…],
 "structuredContent":{…},"_meta":{"io.modelcontextprotocol/serverInfo":{…}}}}
```

Ère legacy — mêmes contenus **sans** `resultType`, sans `_meta`, sans indices
de cache : les clients plus anciens ne connaissent pas ces champs.

Un appel d'outil réussi renvoie un ou deux blocs de texte : le premier est la
phrase lisible (« 100 km/hr = 27.77777778 m/s »), le second la version JSON,
comme le recommande la spécification pour les clients qui ne lisent pas encore
`structuredContent`.

### 8.5 Erreurs JSON-RPC

| Code | Nom | Quand le serveur l'émet |
| --- | --- | --- |
| `-32700` | Parse error | la ligne reçue n'est pas du JSON (réponse avec `id: null`) |
| `-32600` | Invalid request | le message n'est pas un objet JSON-RPC valide (`jsonrpc` ≠ `"2.0"`, `method` absente) |
| `-32601` | Method not found | méthode inconnue, ou `ping` en ère modern ; `data.supportedMethods` liste les méthodes servies |
| `-32602` | Invalid params | `_meta` absent ou incomplet, argument d'outil invalide, nom d'outil inconnu (le message rappelle les noms valides) |
| `-32603` | Internal error | exception inattendue (bogue) ; les erreurs d'usage normales sont forcément capturées par les outils |
| `-32022` | UnsupportedProtocolVersion | version de protocole demandée non supportée |

Les codes `-32020` (HeaderMismatch) et `-32021`
(MissingRequiredClientCapability) ne sont jamais émis : le premier concerne le
transport HTTP (en-tête `MCP-Protocol-Version`), que ce serveur n'implémente
pas, et le second une capacité qu'aucun outil ne requiert (un client sans
`elicitation`, `sampling` ou `roots` fonctionne exactement pareil).

Un échec **métier** (unité inconnue, unités incompatibles, valeur illisible)
n'est jamais une erreur JSON-RPC : c'est un résultat avec `isError: true` dont
le second bloc de texte est un objet JSON `{"error_code": …, "message": …,
"suggestions": […]}`. Ce choix suit la spécification (« tool execution errors
should be reported in the result ») et sert au modèle : il lit l'explication et
corrige son appel.

### 8.6 Journalisation

Le serveur n'envoie **aucune** notification `notifications/message` : la
spécification n'autorise un serveur à en émettre que pour une requête qui
portait un `logLevel` dans ses `_meta`, et la journalisation est dépréciée par
la révision 2026-07-28. Les traces utiles existent en revanche côté processus :
`--verbose` les écrit sur **stderr**, où le client peut les lire sans perturber
le protocole. `logLevel` est donc accepté et sans effet.

### 8.7 Cache

`server/discover` et `tools/list` renvoient `ttlMs: 3600000` (une heure) et
`cacheScope: "public"`, comme l'exige la révision moderne. C'est exact : les
définitions d'outils ne dépendent d'aucun argument et la base d'unités est
embarquée, donc identique pour tous les clients ; le champ `listChanged: false`
confirme que la liste ne changera pas pendant la vie du processus.
`tools/call` ne porte pas d'indice de cache (résultat dépendant des arguments).

### 8.8 Transport stdio

- **une ligne = un message** ; `json.encode` n'insère aucun saut de ligne, il
  n'y a donc jamais de JSON multi-ligne ;
- **stdout ne contient que les réponses** ; toute trace (`--verbose`,
  avertissements, démarrage) va sur stderr ;
- les lignes vides sont ignorées ;
- la fermeture de stdin est le signal d'arrêt normal : le serveur finit les
  réponses en cours, vide le tampon et sort avec le code 0 ;
- `SIGTERM`/`SIGINT` provoquent une sortie propre (code 0) — l'installation des
  gestionnaires est tolérante aux plateformes qui ne les supportent pas
  (Windows) ;
- aucun délai n'est imposé aux requêtes : chaque outil est synchrone et rend la
  main en quelques millisecondes (la base est lue une fois au démarrage).

---

## 9. Architecture du code

```
lib/core/                     moteur de conversion, Dart pur (aucun import Flutter)
  unit_exceptions.dart        UnitDataException, UnitConversionException, UnitErrorCode
  unit_database.dart          lecture de units.json, index par nom, recherche partielle
  unit_expression.dart        analyse « km/hr », réduction en unités de base, conversion
  conversion_engine.dart      API de haut niveau : convert(), parseValue(), describeUnit(), …
  unit_json.dart              forme JSON d'une unité, partagée CLI/MCP
  app_info.dart               version et site du projet
lib/mcp/                      le protocole
  mcp_protocol.dart           versions (2026-07-28 + les quatre révisions anciennes),
                              clés `_meta`, codes d'erreur, exceptions JSON-RPC
  json_schema.dart            validateur JSON Schema des arguments d'outils
  mcp_tools.dart              les cinq outils : schémas, descriptions, exécution
  mcp_server.dart             le serveur : ères, méthodes, résultats, erreurs
  mcp_stdio.dart              transport stdio, gestion des signaux
lib/cli/
  database_locator.dart       recherche et chargement des données, langues
  cli_app.dart                commandes, sorties texte/JSON
bin/convertall.dart           entrée de la ligne de commande
bin/convertall_mcp.dart       entrée du serveur MCP
```

Deux points de conception méritent d'être connus avant de modifier ce code.

**1. Le moteur est un portage, pas un import.** `lib/model/` (modèle de
l'application graphique) dépend de Flutter : `UnitData.loadData()` lit
`assets/units.json` par le *bundle* d'assets, `UnitAtom.parse()` s'appuie sur
l'état statique `UnitController.unitData`, et le formatage des nombres lit les
préférences `shared_preferences`. Un binaire de ligne de commande ne peut rien
faire de tout cela. `lib/core/` rejoue donc le même algorithme en Dart pur, sur
le même fichier de données. Les écarts sont volontaires, peu nombreux et
documentés :

| Écart | Raison |
| --- | --- |
| la base d'unités est passée en paramètre | `lib/model/` la lit dans un état statique lié à l'interface |
| les assistants d'édition (position du curseur, remplacement d'une unité) ne sont pas portés | ils n'ont de sens que dans un champ de saisie |
| `reduce()` est idempotent et ne plante pas hors d'une table d'interpolation | un serveur ne doit jamais mourir sur une entrée valide |
| le signe moins Unicode des six unités de Planck et des constantes est normalisé | l'application le laisse à `eval_ex` |
| un résidu inférieur à 1e-10 est ramené à zéro quand une équation intervient | l'application afficherait `5.68e-14` au lieu de `0` pour 32 °F |

`test/core/parity_test.dart` compare les deux implémentations unité par unité,
conversion par conversion, et échoue si l'une prend du retard sur l'autre :
c'est le garde-fou contre la divergence. Un futur chantier peut extraire le
moteur commun et faire dépendre `lib/model/` de `lib/core/` ; ce n'est pas fait
ici parce que cela toucherait l'application graphique, qui doit continuer de
fonctionner.

**2. Les mêmes gestionnaires pour les deux interfaces.** `lib/cli/cli_app.dart`
n'implémente pas la conversion : il appelle les outils de `lib/mcp/mcp_tools.dart`
et affiche leur résultat. `convertall convert 100 km/hr m/s` et un appel MCP
`convert_value` exécutent le **même** code, donc rendent la même valeur, les
mêmes messages et les mêmes suggestions. Une correction d'ergonomie profite
toujours aux deux.

---

## 10. Tests

    $ flutter test test/core/ test/mcp/

| Fichier | Ce qu'il vérifie |
| --- | --- |
| `test/core/conversion_engine_test.dart` | valeurs de référence (27.77777778 m/s, 96.56064 km/hr, 1055.05585262 J, 212 °F, ...), unités non linéaires (C, F, gas mark, liter per 100 km), notations, refus et codes d'erreur, suggestions |
| `test/core/parity_test.dart` | parité entre `lib/core/` et le modèle de l'application (`lib/model/`) sur des expressions et des conversions |
| `test/mcp/mcp_server_test.dart` | les deux ères, `server/discover`, `tools/list`, les cinq outils, validation des arguments, codes d'erreur, notifications, `ping`, cache |

Vérification manuelle d'un outil, sans client MCP :

    $ printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"convert_value","arguments":{"value":"1","from":"mile","to":"km"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}' \
      | dart run bin/convertall_mcp.dart --verbose

`--verbose` écrit sur stderr la trace des échanges (`<- tools/call`,
`-> error for …`), ce qui rend le débogage lisible.

---

## 11. Limites connues et suite

| Limite | Raison / piste |
| --- | --- |
| Transport stdio seulement | c'est le transport attendu par les clients de bureau ; `streamable-http` demanderait la gestion des en-têtes `Mcp-*`, des sessions et de l'authentification, sans usage local identifié |
| Pas de `resources`/`prompts` | sans valeur pour un convertisseur (voir §7) |
| Pas de pagination | les listes servies sont bornées (`limit` ≤ 500) et tiennent en une réponse |
| Journalisation MCP absente | dépréciée en 2026-07-28 ; les traces vont sur stderr |
| `lib/core/` duplique l'algorithme de `lib/model/` | choix assumé le temps de la transition, surveillé par `parity_test.dart` (§9) |
| Devises non converties | la base ConvertAll n'a pas de taux de change (et cela demanderait un réseau, donc un comportement non reproductible) |

---

## 12. Références

- Spécification MCP 2026-07-28 — <https://modelcontextprotocol.io/specification/2026-07-28>
  (découverte : `/server/discover`, outils : `/server/tools`, cache :
  `/server/utilities/caching`, transport stdio : `/basic/transports/stdio`)
- Révisions antérieures — <https://modelcontextprotocol.io/specification/2025-11-25>
  (cycle de vie : `/basic/lifecycle`)
- Spécification des outils de conversion de ConvertAll : [CLI.md](CLI.md)
- Journal des versions : [`CHANGELOG.md`](../CHANGELOG.md)
