---
# Utilisation
---
## Combiner des unités
---

La véritable force de ConvertAll est sa capacité à combiner plusieurs unités.
Saisissez simplement les noms d'unités séparés par un « * » ou un « / ». Cela
permet de saisir des unités comme « ft * lbf » ou « mi / hr ». Le symbole « ^ »
sert aux exposants, par exemple « ft^3 » ou « ft * lbm / sec^2 ». Les exposants
négatifs sont acceptés, comme « sec^-1 » (par seconde), mais ils peuvent
inverser le symbole de multiplication ou de division (« ft * sec^-2 » devient
« ft / sec^2 »).

La multiplication et la division ont la même priorité : elles sont donc
évaluées de gauche à droite. Les parenthèses permettent de regrouper des unités
au dénominateur : « m / sec / kg » peut aussi s'écrire « m / (sec * kg) ».
Cette dernière forme est probablement plus claire.

Un clic ou un appui sur une unité de la liste remplace en général l'unité la
plus proche du curseur.

Le bouton d'effacement de la barre du haut (icône avec une croix) vide les
champs d'unités pour en saisir de nouvelles.

Le bouton de filtre de la barre du haut (icône en entonnoir) n'affiche qu'un
seul type d'unité dans la liste. À noter : il ne montre pas les unités qui
pourraient être combinées pour former ce type.
