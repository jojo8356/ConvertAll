# ConvertAll — Direction artistique « Instrument de précision »

Document de référence de l'interface. Il décrit **la DA réellement codée** :
chaque valeur ci-dessous se retrouve à l'identique dans
`lib/model/theme_model.dart` (source unique des jetons) et dans les widgets de
`lib/gui/`. Toute évolution de style doit passer par ce fichier de jetons,
jamais par une couleur écrite « en dur » dans une vue.

- Version du document : 1.0 — 2026-10-11
- Remplace l'ancienne palette (crème `#f3d5b5` + bleu marine `#03045e` en
  clair, cyan `#00b4d8` en sombre), qui n'avait ni hiérarchie de plans, ni
  états d'interaction documentés, ni contraste vérifié.

---

## 1. Étude du produit (constats qui ont guidé la DA)

ConvertAll est un convertisseur d'unités « libre » : l'utilisateur **tape**
`ft * lbf / hr` au lieu de choisir dans des listes fermées. L'écran principal
est donc un instrument de saisie à quatre zones :

| Zone | Rôle | Contenu typique |
|---|---|---|
| Unités « De » | ce que l'on saisit | `ft * lbf / hr` |
| Liste des unités | aide au choix / contrôle | nom, type, commentaire |
| Unités « Vers » | ce que l'on obtient | `N * m / sec` |
| Valeurs | le résultat | `12.5` → `1.6945` |

Constats :

1. **Le résultat est la donnée reine.** Les chiffres doivent être gros,
   alignés (chiffres tabulaires) et comparables d'une ligne à l'autre.
2. **Deux côtés d'une même conversion.** L'œil doit distinguer instantanément
   « De » et « Vers » sans lire les libellés → **deux accents distincts**.
3. **Le clavier est l'outil principal** (`↑ ↓`, `Entrée`, `Tab`, `Échap`,
   `Page ↑/↓`). Les raccourcis doivent être visibles, pas cachés dans une aide.
4. **La table des unités est un référentiel**, pas une décoration : beaucoup de
   lignes, un tri, un filtre, donc une tête de table collante et des lignes
   denses mais respirantes.
5. **L'utilisateur peut se tromper d'unité** : un retour immédiat
   (valide / partiel / erreur) vaut mieux qu'un message d'erreur global.
6. **Usage long, y compris de nuit** : le thème sombre est un vrai thème, pas
   un simple inversement.

## 2. Intention

**« Instrument de précision »** : sobre, net, sans ornement ; surfaces
neutres froides, un seul accent par côté, et de la couleur **uniquement pour
informer** (sélection, validité, erreur). Rien n'est décoratif : chaque
bordure, chaque teinte a une fonction.

Trois règles simples :

1. **La couleur porte un sens, jamais une ambiance.**
2. **La donnée d'abord** : chiffres tabulaires, libellés courts en
   majuscules, plans séparés par des filets fins.
3. **Tout état est visible** : survol, sélection clavier, champ actif, valeur
   copiée, unité incomplète.

## 3. Palette

Deux palettes (jour / nuit) strictement parallèles : mêmes rôles, mêmes
contrastes. Contrastes vérifiés **WCAG AA (≥ 4,5:1)** pour le texte courant.

### 3.1 Rôles système (`ColorScheme`)

| Rôle | Sens dans ConvertAll | Clair | Sombre |
|---|---|---|---|
| `primary` | accent « De », focus, sélection | `#1E5AE8` | `#7AA2FF` |
| `onPrimary` | texte sur accent | `#FFFFFF` | `#0A1A3D` |
| `primaryContainer` | ligne sélectionnée, badge « De » | `#DCE8FF` | `#1E3A72` |
| `tertiary` | accent « Vers » | `#4F46E5` | `#A5A1FF` |
| `tertiaryContainer` | badge « Vers » | `#E6E4FF` | `#2E2A6E` |
| `secondary` | commandes neutres, en-têtes | `#4F5B76` | `#9FB0CC` |
| `error` | unité inconnue, valeur invalide | `#BB3021` | `#FF8B7B` |
| `surface` | fond des panneaux | `#FFFFFF` | `#121A2B` |
| `onSurface` | texte principal | `#101828` | `#E9EEF7` |
| `onSurfaceVariant` | texte secondaire, libellés | `#5A6880` | `#A3B2CB` |
| `outline` | bordure de champ actif | `#B9C4D6` | `#465570` |
| `outlineVariant` | filets, séparateurs | `#DCE3ED` | `#26314A` |
| `inverseSurface` | info-bulles, snackbars | `#24303F` | `#E9EEF7` |

### 3.2 Jetons propres à la DA (`AppColors`, lus par `AppColors.of(context)`)

| Jeton | Fonction | Clair | Sombre |
|---|---|---|---|
| `canvas` | fond de page, derrière les panneaux | `#EDF1F7` | `#0A1120` |
| `panel` | fond d'un panneau / d'une carte | `#FFFFFF` | `#121A2B` |
| `hairline` | filets, bordures de panneaux, séparateurs de lignes | `#DCE3ED` | `#26314A` |
| `sunken` | fond des champs (creusé) | `#F7F9FC` | `#161F33` |
| `sunkenStrong` | en-têtes de table, pastilles de touche | `#EDF1F8` | `#1B2740` |
| `hover` | voile de survol (lignes, boutons) | `#0F1E5AE8` | `#14FFFFFF` |
| `highlight` | ligne pointée au clavier | `#1A1E5AE8` | `#247AA2FF` |
| `focusRing` | halo du champ actif | `#331E5AE8` | `#4D7AA2FF` |
| `accentSoft` | fond d'une pastille accentuée / puce cochée | `#E6EDFD` | `#1C2B4D` |
| `success` | unités compatibles, copie réussie | `#147A4B` | `#48C98B` |
| `warning` | saisie partielle, filtre actif | `#9A6100` | `#E0B04C` |
| `danger` | erreur (reprend `error`) | `#BB3021` | `#FF8B7B` |

### 3.3 Fond de la version web

La version web affiche la fenêtre comme une carte flottante 830 × 700 :
fond `webBackdropLight` `#DCE3ED` / `webBackdropDark` `#060B14`, rayon
`webRadius` 20 px.

## 4. Typographie

Police système (aucune police embarquée : poids du paquet minimal). Échelle :

| Style | Taille | Poids | Usage |
|---|---|---|---|
| `titleLarge` | 20 | 600 | titre de vue (Bases, Fractions, Aide) |
| `titleMedium` | 16,5 | 600 | titre d'`AppBar`, titre de section |
| `titleSmall` | 14 | 600 | sous-titre, titre de panneau |
| `bodyLarge` | 15 | 400 | saisie d'unités, texte courant |
| `bodyMedium` | 14 | 400 | texte de formulaire |
| `bodySmall` | 12,5 | 400 | aides, commentaires, unités réduites |
| `labelLarge` | 13 | 600 | libellés de boutons |
| `labelMedium` | 11,5 | 600 | libellés courts |
| `labelSmall` | 11 | 600 | mention légale, version |

Styles de la DA :

| Style | Taille | Détail | Usage |
|---|---|---|---|
| `AppTheme.overline` | 10,5 | 700, interlettre 1,4, majuscules | libellés « DE », « VERS », « UNITÉS », en-têtes de table |
| `AppTheme.unitText` | 15 | chiffres tabulaires | expression d'unité (`ft * lbf / hr`) |
| `AppTheme.valueText` | 22 | 600, chiffres tabulaires | le résultat converti |
| `AppTheme.codeText` | 12,5 | chiffres tabulaires | raccourcis, unité réduite, base numérique |

Règle : **tous les nombres sont en chiffres tabulaires** (`FontFeature.
tabularFigures`) pour qu'une colonne de valeurs reste alignée.

## 5. Espacement, formes, profondeur

| Jeton | Valeur | Usage |
|---|---|---|
| `gapXs` | 4 | entre une icône et son texte |
| `gapS` | 8 | entre deux éléments d'un même groupe |
| `gapM` | 12 | padding interne standard |
| `gapL` | 16 | entre deux panneaux, marge de page |
| `gapXl` | 24 | respiration autour d'un contenu isolé |
| `panelRadius` | 14 | cartes / panneaux |
| `fieldRadius` | 10 | champs, boutons |
| `webRadius` | 20 | carte de la version web |

**Profondeur** : pas d'ombre portée, la hiérarchie vient de **trois plans** —
`canvas` (page) → `panel` (carte, filet `hairline`) → `sunken` /
`sunkenStrong` (contenu creusé). Les ombres sont réservées aux surfaces
flottantes (menus, snackbars, boîtes de dialogue).

## 6. Composants

### Panneau (`PanelCard`)
Carte `panel` + filet `hairline` 1 px + rayon 14. Un liseré d'accent de 3 px à
gauche (facultatif) identifie un côté de conversion. Aucune ombre.

### Champ de saisie (`LabelledTextEditor`, `ValueField`)
Libellé `overline` **au-dessus** du champ. Champ creusé `sunken`, filet
`hairline` au repos, `outline` au survol, `primary` 1,6 px + halo `focusRing`
au focus, `danger` en erreur. Rayon 10.

### Bouton d'échange (« swap »)
Entre les deux champs d'unités : bouton unique qui inverse les côtés. Au
survol, `hover` ; au clic, appel `swapUnits()` du modèle (les deux textes
d'unités sont échangés, la valeur saisie change de côté).

### Table des unités
- En-tête collant 40 px, fond `sunkenStrong`, libellés `overline`,
  indicateur de tri (`unfold_more` / `arrow_downward` / `arrow_upward`).
- Lignes de 30 px : nom (+ abréviation), type, commentaire —
  272 / 150 / 296 px dans une largeur utile de 750 px.
- États : survol (`hover`), ligne sélectionnée à la souris
  (`primaryContainer` + marqueur 3 px), ligne pointée au clavier (`highlight`),
  aucune correspondance (état vide explicite).

### Étiquette de touche (`KeyHint`)
Pastille bordée `hairline` sur fond `panel`, rayon 5, texte `codeText` en 600,
suivie de l'action en `bodySmall` : `↑ ↓` parcourir, `Entrée` choisir,
`Tab` champ suivant. Toujours dans le pied de la fenêtre principale.

### Barre d'état (`InfoBar`)
Icône 17 px + message en 600, sur un fond teinté à 9 % de la couleur d'état et
une bordure à 28 %, rayon 10 (couleur prise dans `success` / `warning` /
`danger` / `secondary` selon le cas). Détail technique facultatif dans une
pastille `sunkenStrong` en `codeText`. Elle dit *pourquoi* la conversion
n'aboutit pas (« unités de types différents »), sans bloquer la saisie.

### Voyant de validité (`ValidityDot`)
Pastille 8 px **et** libellé 11 px, en fin de champ d'unité : `success` +
`valid` (unité reconnue), `danger` + `invalid` (inconnue), `outline` + `empty`
(champ vide). Le libellé garantit que l'information ne repose pas sur la seule
couleur.

### État vide (`EmptyState`)
Icône 26 px (`outline`) ou anneau de chargement 2,4 px, titre en `bodyMedium`
600, message en `bodySmall`, centré avec `gapL` de marge : « Aucune unité ne
correspond au filtre », « Unités en cours de chargement ».

### Pastille d'icône (`IconBadge`)
Carré arrondi de 28 px (rayon 32 % de la taille), fond à 14 % de la couleur,
icône à 58 % : utilisée en tête des vues utilitaires (Bases, Fractions, Aide,
boîtes de dialogue).

### Aide (`HelpView`)
Markdown dans une carte `panel` en `SelectionArea`, largeur max 780 px,
marges `gapXl` / `gapL`. Liens externes ouverts dans le navigateur, liens
`.md` dans un historique interne (précédent / suivant / sommaire / fermer).

## 7. Interaction et accessibilité

- **Focus toujours visible** : anneau `primary` 1,6 px + `focusRing`.
- **Survol discret** : voile `hover` (≤ 8 % d'opacité) — jamais un
  changement de couleur du texte.
- **Couleur jamais seule** : chaque état coloré a une icône ou un texte
  (valide = pastille *et* valeur affichée, erreur = icône *et* message).
- **Cibles ≥ 30 × 30 px** (`CopyIconButton`), boutons 40 px de haut.
- **Chiffres tabulaires** partout, espaces insécables avant les unités.
- **Thème sombre** : contraste ≥ 7:1 sur le texte principal, surfaces bleutées
  froides (pas de noir pur, pas de gris chaud).
- **Zoom d'interface** 0,25 → 4,0 (préférence `view_scale`) : mise en page
  fluide, largeur de contenu fixe 782 px pour que la table reste lisible.
- **Clavier** : `↑ ↓` parcourir la liste, `Page ↑/↓` par pages, `Entrée`
  choisir l'unité pointée, `Tab` champ suivant, `Échap` fermer, `Ctrl+Q`
  quitter (bureau uniquement).

## 8. Fenêtre

| Constante | Valeur |
|---|---|
| `_stdWidth` / `_stdHeight` | 830 × 700 (taille de référence du contenu) |
| `minWidth` / `minHeight` | 520 × 560 |
| Largeur de contenu (`_contentWidth`) | 782 |
| Espace central (`_centerGap`) | 64 |
| Largeur de table (`tableWidth`) | 750 |

## 9. Iconographie

- Icônes **Material** uniquement (aucune police d'icônes exotique), taille 20,
  couleur `onSurfaceVariant` au repos, `primary` / `tertiary` pour les côtés,
  `danger` pour les erreurs.
- **Icône de l'application** (refaite pour la DA) : deux flèches d'échange
  épaisses — azur `#6E9BFF` (De) et indigo `#A9A6FF` (Vers) — sur un carré
  arrondi marine `#121E38 → #0A1120`. Déclinée en 32/48/64/108/512/1024 px
  plus la hiérarchie `hicolor` pour Linux.

## 10. Version de départ (avant/après)

| Élément | Avant | Après |
|---|---|---|
| Accent | un seul bleu `#03045e`, utilisé partout | azur (De) + indigo (Vers), azur réservé au focus et à la sélection |
| Fonds | crème `#f3d5b5` / blanc cassé | trois plans : `canvas` / `panel` / `sunken` |
| Typographie | 14 partout, sans hiérarchie | échelle 20 → 10,5, chiffres tabulaires, libellés majuscules |
| États | aucun documenté (survol par défaut) | survol / sélection / focus / erreur définis (voir §6) |
| Retour utilisateur | dialogue d'erreur | `ValidityDot` + `InfoBar`, la saisie n'est jamais bloquée |
| Raccourcis | dans l'aide | toujours visibles (`KeyHint`) |
| Sombre | inversion approximative | palette sombre complète, contrastes AA |

## 11. Langue et adaptations

L'interface suit la langue du système au premier démarrage, et peut être
forcée en anglais ou en français dans *Réglages → Apparence → Langue*. Le
choix est mémorisé (`prefs`, clé `language`).

* Tous les textes visibles passent par `context.l10n.<clé>` (`AppLocalizations`,
  généré depuis `lib/l10n/app_*.arb`), jamais par une chaîne en dur ; les
  modèles sans `BuildContext` utilisent `lookupAppLocalizations`.
* Le français est environ 15 % plus long que l'anglais : les libellés courts
  sont préférés (`Unité`, `Type`, `Base`) et aucune largeur de colonne ne
  dépend du texte (elles sont fixes, dans `unit_table.dart`).
* Les ressources traduites suivent la langue choisie : `assets/help/fr/` pour
  l'aide et `assets/units_fr.json` pour les types d'unités (les noms et
  abréviations d'unités restent en anglais : ce sont les valeurs saisies).
* Les nombres insérés dans un message (`{base}` dans « Base : {base} »)
  passent par `intl`, donc par les règles de la langue. Les résultats de
  conversion, eux, gardent la notation neutre de Dart (point décimal, chiffres
  tabulaires) : la virgule française n'est pas encore appliquée, car elle
  changerait les valeurs affichées et copiées.

## 12. Ce qu'il ne faut pas faire

1. Écrire une couleur `Color(0x…)` (ou un `Colors.bleu`) dans une vue : tout
   passe par `theme_model.dart`.
2. Ajouter un troisième accent coloré : il n'y a que « De », « Vers » et les
   couleurs d'information.
3. Utiliser la couleur pour décorer (dégradé, ombre colorée, texte en
   `primary` sans lien ni action).
4. Introduire une police embarquée : la taille du paquet est prioritaire.
5. Descendre sous 12,5 px pour un texte utile (les mentions légales seules
   peuvent utiliser 11 px).
6. Écrire un texte visible en dur dans une vue : il doit exister dans
   `lib/l10n/app_en.arb` et `app_fr.arb` (voir §11).
