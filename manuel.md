# 🖥️ MINITEL_GC — Système d'Exploitation & Suite Télématique 3615 MAGIS CLUB

Bienvenue sur la documentation officielle de **`minitel_gc`**, un environnement d'exploitation complet, modulaire et autonome écrit en **Lua 5.3** pour terminal **Minitel (Magis Club)** connecté en série à un **Raspberry Pi** (ou exécuté directement sur PC en mode émulation VT100).

---

## ⚙️ 1. ARCHITECTURE TECHNIQUE & FONCTIONNEMENT BAS NIVEAU

### 1.1 Liaison Série & Mode 80 Colonnes (VT100)
Contrairement au mode Vidéotex standard d'origine (40 colonnes à 1200/75 bauds), le système `minitel_gc` exploite le **mode téléinformatique 80 colonnes (émulation VT100)** du Minitel à la vitesse maximale de **9600 bauds (8 bits de données, sans parité, 1 bit d'arrêt - 8N1)**.

Au démarrage de `master.lua`, l'opérateur bascule le Minitel via les séquences matérielles :
1. **Mode 80 colonnes (Téléinformatique)** : `Ctrl + Esc` puis `T` puis `A`
2. **Suppression de l'écho local (Echo OFF)** : `Ctrl + Esc` puis `T` puis `E`
3. **Clavier étendu (Flèches & Fonctions)** : `Ctrl + Esc` puis `C` puis `E`

Le moteur système configure alors `/dev/ttyUSB0` via `stty` en mode `raw -echo -icanon min 0 time 0`. Cela permet une lecture **non-bloquante** cycle par cycle : l'interpréteur Lua ne fige jamais l'exécution en attendant une touche.

### 1.2 L'Optimisation Graphique : Le "Delta-Drawing"
Même à 9600 bauds, la ligne série ne peut transmettre qu'environ **960 octets par seconde**. Un écran complet de $80 \times 24$ caractères représente $1\,920$ octets (soit 2 secondes pleines de balayage visible).
Pour obtenir une fluidité digne d'une console de jeu, `minitel_gc` applique trois règles strictes :
* **Squelette Statique** : Les cadres (`+---+`), bandeaux et bordures ne sont envoyés qu'une seule fois à l'initialisation du module.
* **Rafraîchissement Différentiel (Delta-Drawing)** : Lors d'un déplacement de curseur (dans un lanceur, un tableur ou l'explorateur de fichiers), seules les coordonnées ANSI `\x1b[Y;XH` de l'ancienne ligne (pour retirer la surbrillance `\x1b[0m`) et de la nouvelle ligne (pour appliquer la vidéo inverse `\x1b[7m`) sont transmises (~80 octets au lieu de 1 920).
* **Fenêtrage Matériel ANSI (`\x1b[3;24r`)** : Utilisé dans l'éditeur et l'interpréteur BASIC pour verrouiller les deux lignes de statut supérieures tout en laissant le reste de l'écran défiler nativement.

### 1.3 Le SDK Système (`minitel.lua`)
Le fichier `minitel.lua` agit comme une bibliothèque dynamique (API) partagée par tous les programmes :

| Fonction du SDK                   | Rôle Technique                                                                                                                                                                                              |
| :-------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `minitel.init()` / `cleanup()`    | Auto-détecte si le programme tourne sur le Minitel (`/dev/ttyUSB0`) ou sur un PC de développement, configure `stty` et gère le curseur matériel.                                                            |
| `minitel.get_key()`               | Décodeur matériel de séquences d'échappement ANSI/VT100. Traduit les séquences multi-octets en constantes lisibles (`ENVOI`, `RETOUR`, `CORRECTION`, `ANNULATION`, `REPETITION`, `GUIDE`, `UP`, `DOWN`...). |
| `minitel.play_sound(type)`        | Synthétiseur audio asynchrone. Appelle `play` (SoX) en tâche de fond (`&`) pour générer des ondes carrées (`square`) ou dents de scie (`sawtooth`) sans ralentir l'affichage.                               |
| `minitel.draw_window(x,y,w,h,t)`  | Trace une fenêtre encadrée aux coordonnées `(x,y)` avec un titre centré en vidéo inverse.                                                                                                                   |
| `minitel.progress_bar(...)`       | Génère une jauge graphique proportionnelle (`[######....] 60%`) pour les points de vie, les stocks ou la télémétrie.                                                                                        |
| `minitel.msg_box` / `confirm_box` | Boîtes de dialogue modales (alertes et choix `[ OUI ]` / `[ NON ]`) gérées en une seule ligne de code.                                                                                                      |
| `minitel.input_box(...)`          | Champ de saisie modal sécurisé supportant l'effacement caractère par caractère (`CORRECTION`) ou la purge complète de la ligne (`ANNULATION`).                                                              |
| `minitel.file_browser(mode, dir)` | Explorateur de fichiers visuel style *Norton Commander* (`OPEN` / `SAVE`) avec barre de défilement et navigation dans l'arborescence Linux.                                                                 |

### 1.4 Système de Sauvegarde par Sérialisation Lua
Les applications et jeux (`calc.lua`, `bourse.lua`, `anomalie.lua`) n'utilisent pas de formats lourds comme XML. Lors d'une sauvegarde via `minitel.file_browser("SAVE", ...)`, l'état mémoire du programme est sérialisé directement sous forme de table Lua native (`return { ... }`). Au chargement, la fonction native `loadfile()` recompile les données en mémoire en moins d'une milliseconde.

---

## 🕹️ 2. MANUEL DES JEUX & LORE DE L'UNIVERS MAGIS

Tous les jeux sont accessibles depuis le portail **`3615 JEUX`** (`launcher_jeux.lua`), qui inspecte dynamiquement les métadonnées (`-- @GENRE:` et `-- @DESC:`) de chaque cartouche `.lua`.

---

### 🌐 A. RPG : ENIGMA (`jeux/minitel_rpg.lua`)
#### 📖 Le Lore
*Année 1988. En composant le code expérimental `3615 ENIGMA`, vous avez déclenché un protocole militaire oublié sur le réseau Transpac. Le verrou cryptographique s'est brisé et votre conscience a été numérisée et aspirée dans les couches profondes du serveur central. Désormais prisonnier de la matrice X.25 sous la forme d'un processus Root (`@`), vous devez descendre de nœud en nœud, affronter les daemons corrompus et appliquer des patchs de code pour éviter la corruption totale de votre mémoire.*

#### 🎮 Manuel de Fonctionnement
* **Exploration temps réel** : Vous incarnez `@` dans un réseau de salles générées procéduralement.
  * `#` : Paroi de données infranchissable.
  * `+` : **Patch de code** (Restaure entre 15 et 25 points d'Intégrité `INT`).
  * `*` : **Cycle Processeur** (Augmente définitivement votre Overclocking `OVC +1`, soit vos dégâts).
  * `>` : **Passerelle** vers le nœud inférieur (la difficulté et la réplication des menaces augmentent à chaque étage).
* **Système de Combat** : Dès qu'un programme hostile (*Worm Basique*, *Trojan Caché*, *Logiciel Rançon*, *Noyau Fantôme*) vous intercepte, l'écran bascule sur la console de contre-mesures :
  1. **`[ INJECTION ]`** : Attaque standard ultra-fiable (95 % de précision).
  2. **`[ OVERLOAD ]`** : Surcharge brutale (60 % de précision, mais triple le bonus d'Overclocking `OVC`).
  3. **`[ PATCHER ]`** : Compile un soin d'urgence pendant le tour de combat.
  4. **`[ ABORT ]`** : Tente de couper la liaison (50 % de chance) et disperse les programmes ennemis sur la carte.
* **Configuration Matérielle** : Depuis l'écran titre, vous pouvez reconfigurer les paramètres du serveur (Intégrité de départ, densité des salles, taux de réplication) sauvegardés dans `jeux/minitel_rpg.cfg`.

---

### 💼 B. 3615 BOURSE (`jeux/bourse.lua`)
#### 📖 Le Lore
*Fin des années 80 : l'âge d'or de la télématique française. Vous êtes un courtier indépendant fraîchement débarqué sur le marché gris des composants électroniques. Vous démarrez à Paris-Vélizy avec 2 500 Francs en poche, un coffre de voiture de 100 places, mais surtout une **dette écrasante de 5 000 Francs** contractée auprès d'un usurier qui applique **8 % d'intérêts par jour**. Vous avez exactement **30 jours** pour sillonner la France (Paris, Chaumont, Reims, Lyon, Grenoble, Rennes), spéculer sur les processeurs Z80 et les EPROM, rembourser votre dette et bâtir un empire.*

#### 🎮 Manuel de Fonctionnement
* **Analyse des Cours** : À gauche s'affichent les 8 composants et leur tendance par rapport à la veille :
  * `+` ou `-` : Hausse ou baisse marquée.
  * `!` : **Pénurie industrielle** (les prix triplent, moment idéal pour vendre !).
  * `v` : **Déstockage massif** (prix divisés par 3, achetez tout ce que vous pouvez !).
* **Commandes** :
  * **`[Z]` / `[S]`** : Sélectionner un composant (le panneau inférieur indique votre **Prix d'Achat Moyen** pour ne jamais vendre à perte).
  * **`[A]` ou `[ENVOI]`** : Acheter (le calculateur pré-remplit automatiquement le maximum achetable selon votre liquide et la place libre dans le coffre).
  * **`[V]`** : Vendre (affiche la marge nette par unité avant validation).
  * **`[B]`** : Accéder à la **Caisse Nationale Télécom** pour rembourser votre dette ou placer vos liquidités sur un livret d'épargne rémunéré à **+3 % par jour**.
  * **`[T]`** : Voyager vers une autre ville (consomme 1 journée et déclenche des événements aléatoires : contrôle de la brigade des PTT, garagiste proposant d'agrandir le coffre...).
  * **`[RETOUR]`** : Menu Système permettant de sauvegarder/charger votre carrière via l'explorateur de fichiers.

---

### 📡 C. 3615 ANOMALIE (`jeux/anomalie.lua`)
#### 📖 Le Lore
*Vous êtes l'Opérateur de garde de la Station Relais du Secteur 4, un complexe souterrain chargé de router les trames Télétel nationales. À la suite d'une surtension inexpliquée, vous reprenez connaissance dans le sas principal plongé dans le noir. L'air sent l'ozone, les systèmes de sécurité autonomes sont devenus hostiles et le calculateur central VAX menace de s'effondrer.*

#### 🎮 Manuel de Fonctionnement
* **Mécanique** : Livre dont vous êtes le héros avec gestion d'état persistante (jauge d'Intégrité `INT`, Crédits et Inventaire d'objets clés).
* **Exploration Conditionnelle** : Certains choix n'apparaissent que si vous possédez l'objet requis dans votre inventaire (ex: le `BADGE` magnétique pour ouvrir la porte blindée, ou la `CLEF_CRYPTO` pour désactiver le drone de maintenance sans subir de dégâts).
* **Commandes** : Touches **`1` à `4`** pour agir, **`[S]`** pour sauvegarder sa progression sur le disque dans `jeux/saves_anomalie/`, **`[C]`** pour charger une sauvegarde.

---

### 🃏 D. 3615 POKER (`jeux/poker.lua`)
#### 📖 Le Lore
*Le salon VIP nocturne du Magis Club. Derrière l'écran cathodique, l'intelligence artificielle du croupier vous attend avec un jeu spécial de 36 cartes télématiques (Nuage, Champi, Fleur, Pièce, Magis, Étoile).*

#### 🎮 Manuel de Fonctionnement
1. **Phase de Mise (`BETTING`)** : Réglez votre mise avec `Haut`/`Bas` ou tapez **`[M]`** pour saisir directement un montant libre, puis appuyez sur **`[ENVOI]`**.
2. **Phase d'Échange (`HOLDING`)** : Déplacez-vous sous vos 5 cartes avec `Gauche`/`Droite` (`Q`/`D`), appuyez sur `Espace` ou `Haut`/`Bas` pour marquer les cartes à **`GARDER`**, puis validez avec **`[ENVOI]`**.
3. **Abattage (`SHOWDOWN`)** : Le croupier révèle son jeu et applique sa propre stratégie d'échange. Les gains vont de `x2` (Paire) jusqu'à `x16` (5 Identiques). Appuyez sur **`[G]`** à tout moment pour consulter la table des gains.

---

## 🧰 3. MANUEL DES UTILITAIRES & EXEMPLES PRATIQUES

Accessibles depuis **`3615 OUTILS`** (`launcher_utils.lua`), ces modules transforment le Minitel en poste de travail bureautique et télématique.

---

### 📊 A. MAGIS CALC (`utils/calc.lua`) — Tableur Multi-Feuilles
Un tableur complet inspiré de *VisiCalc* et *Lotus 1-2-3*, doté d'un moteur d'évaluation mathématique temps réel et d'une gestion multi-feuilles.

* **Navigation** : `Z, Q, S, D` ou Flèches pour déplacer le curseur de `A1` à `Z99`.
* **Édition** : `[ENVOI]` pour saisir un texte, un nombre ou une formule commençant par `=`. `[ANNULATION]` vide instantanément la cellule.
* **Feuilles** : Touches `<` et `>` pour naviguer entre les feuilles du classeur (`FEUIL1`, `FEUIL2`...).
* **Recalcul forcé** : Touche Minitel **`[REPETITION]`** ou **`[SUITE]`**.

#### 💡 Exemple concret : Créer un suivi de budget multi-feuilles
1. Placez-vous en **`A1`**, appuyez sur `[ENVOI]` et tapez `COMPOSANTS`. En **`B1`**, tapez `500`.
2. En **`A2`**, tapez `OUTILLAGE`. En **`B2`**, tapez `250`.
3. En **`A3`**, tapez `LIVRAISON`. En **`B3`**, tapez `50`.
4. Placez-vous en **`B4`** et tapez la formule :
   ```text
   =SOMME("B1:B3")
   ```
   $\rightarrow$ La cellule affiche immédiatement **`800`** !
5. En **`B5`**, calculez la moyenne des dépenses avec :
   ```text
   =MOYENNE("B1:B3")
   ```
6. Appuyez sur **`[RETOUR]`**, choisissez **`[3] AJOUTER UNE FEUILLE`** et nommez-la **`TVA`**.
7. Sur cette nouvelle feuille `TVA`, placez-vous en **`A1`** et récupérez le total de la première feuille majoré de 20 % :
   ```text
   =FEUIL1!B4*1.20
   ```
   $\rightarrow$ La cellule affiche **`960.0`** ! Appuyez sur `[RETOUR]` puis `[5]` pour sauvegarder votre classeur.

---

### 📝 B. MAGIS EDIT (`utils/edit.lua`) — Éditeur de Texte 80 Colonnes
Éditeur plein écran conçu pour la rédaction de notes ou l'écriture de programmes BASIC.
* **Commandes d'édition** : Flèches pour se déplacer, `HOME`/`END` pour aller en début/fin de ligne, `[CORRECTION]` pour effacer un caractère, et **`[ANNULATION]`** pour effacer intégralement la ligne courante.
* **Gestion des fichiers** : Appuyez sur **`[RETOUR]`** pour ouvrir le menu Fichier (Nouveau, Ouvrir via l'explorateur visuel, Sauvegarder sous...). Un indicateur `*` apparaît dans la barre supérieure dès que le fichier en mémoire a été modifié sans être enregistré.

---

### 💻 C. MICRO-BASIC TÉLÉTEL V4.0 (`utils/basic.lua`)
Un interpréteur BASIC interactif complet doté de commandes graphiques spécifiques au Minitel (`LOCATE`, `INVERT`, `NORMAL`, `BEEP`, `MKEY()`).

* **Commandes système** : `LIST` (voir le code), `RUN` (exécuter), `NEW` (vider la mémoire), `DIR` (lister les fichiers `.bas`), `SAVE "NOM"`, `LOAD "NOM"`, `EDIT <ligne>`, `HELP` (manuel intégré), `EXIT`.

#### 💡 Exemple concret : Programmer un mini-jeu interactif en BASIC
Dans l'invite `> ` de `basic.lua`, tapez ce programme ligne par ligne :
```basic
10 CLS
20 X = 40
30 Y = 12
40 LOCATE X, Y
50 INVERT
60 PRINT "@" ;
70 NORMAL
80 K = MKEY()
90 IF K = 27 THEN END
100 IF K > 0 THEN LOCATE X, Y
110 IF K > 0 THEN PRINT " " ;
120 IF K = 200 THEN Y = Y - 1
130 IF K = 201 THEN Y = Y + 1
140 IF K = 202 THEN X = X - 1
150 IF K = 203 THEN X = X + 1
160 PAUSE 0.05
170 GOTO 40
```
Tapez ensuite **`RUN`** et validez : vous déplacez un curseur `@` en vidéo inverse sur tout l'écran de votre Minitel avec les flèches ou `ZQSD` ! Appuyez sur **`[RETOUR]`** (`K = 27`) pour arrêter le programme, puis tapez **`SAVE "BALADE"`** pour l'enregistrer sur le disque.

---

### 🚆 D. 3615 TRAIN (`utils/train.lua`) — Panneau SNCF Temps Réel
Transforme le Minitel en tableau d'affichage des départs de gare (type panneau *Solari*).
* **Exemple d'utilisation** :
  1. Au lancement, la boîte modale demande le nom d'une gare (ex: tapez **`CHAUMONT`**, **`REIMS`** ou **`PARIS EST`**) puis appuyez sur `[ENVOI]`.
  2. Le module interroge l'API ferroviaire en pur Lua et affiche les **13 prochains trains** au départ avec l'heure, la destination finale, le numéro de train (`TER`, `TGV`, `IC`) ainsi que la **Voie** ou le **Retard éventuel** (`RET +10M`).
  3. Utilisez `Z`/`S` pour sélectionner un train et appuyez sur **`[ENVOI]`** pour ouvrir sa fiche détaillée, **`[A]`** pour actualiser le panneau en direct, ou **`[N]`** pour changer de gare.

---

### ⛽ E. 3615 CARBURANT (`utils/carburant.lua`) — Observatoire des Prix
Interroge en temps réel le flux gouvernemental `data.economie.gouv.fr` en pur Lua pour comparer le prix à la pompe des stations-service.
* **Exemple d'utilisation** :
  1. Tapez un code postal à 5 chiffres (ex: **`52300`** ou **`52000`**) dans la fenêtre de saisie et appuyez sur `[ENVOI]`.
  2. Le programme télécharge les relevés officiels, **trie automatiquement les stations de la moins chère à la plus chère (sur le Gazole)** et affiche un tableau comparatif **Gazole / SP98 / E10**.
  3. Naviguez avec `Z`/`S` et appuyez sur **`[ENVOI]`** sur une station pour afficher son adresse complète dans une fenêtre pop-up.

---

### 🔄 F. 3615 MISE À JOUR (`updater.lua`) — Synchronisation Git Automatisée
Permet de mettre à jour le système directement depuis le clavier du Minitel :
* Effectue une sauvegarde de sécurité automatique des programmes BASIC locaux (`/home/minitel/minitel_gc_backup`).
* Analyse l'état du dépôt via `git status --porcelain`.
* En cas de fichier modifié localement sur le Minitel, propose 4 stratégies :
  1. **Écraser le local** (`git reset --hard`) pour récupérer la version officielle.
  2. **Commit & Push** directement depuis le Minitel en saisissant un message de commit au clavier !
  3. **Conserver en renommant** les fichiers modifiés avec le suffixe `_local.lua` avant de télécharger la mise à jour.
  4. **Annuler** et revenir au portail.