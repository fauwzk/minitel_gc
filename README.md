# 🖥️ MAGIS CLUB — Guide de l'Utilisateur & Manuel de Référence Technique

```text
================================================================================
   __  __    _    ____ ___ ____     ____ _     _   _ ____  
  |  \/  |  / \  / ___|_ _/ ___|   / ___| |   | | | | __ ) 
  | |\/| | / _ \| |  _ | |\___ \  | |   | |   | | | |  _ \ 
  | |  | |/ ___ \ |_| || | ___) | | |___| |___| |_| | |_) |
  |_|  |_/_/   \_\____|___|____/   \____|_____|\___/|____/ 

        SYSTEME D'EXPLOITATION TELEMATIQUE & MICRO-INFORMATIQUE
          GUIDE DE L'UTILISATEUR ET MANUEL DE REFERENCE TECHNIQUE
================================================================================
Edition : 2026 - Revision 4.2 (Architecture 9600 Bauds / 80 Colonnes VT100)
Materiel Requis : Terminal Minitel (Magis Club) + Coprocesseur Raspberry Pi
================================================================================
```

> **NOTE D'INTENTION :** `minitel_gc` est une plateforme micro-informatique et ludique conçue pour fonctionner sur un **Raspberry Pi** relié au port péri-informatique d'un **Minitel** (ou directement sur PC en émulation VT100). Ce manuel est rédigé dans la tradition des grands guides de référence 8-bits des années 1980 (*Commodore 64 Programmer's Reference Guide*, *Amstrad CPC User Manual*).

---

## 📖 TABLE DES MATIÈRES

- [🖥️ MAGIS CLUB — Guide de l'Utilisateur \& Manuel de Référence Technique](#️-magis-club--guide-de-lutilisateur--manuel-de-référence-technique)
  - [📖 TABLE DES MATIÈRES](#-table-des-matières)
  - [⚙️ CHAPITRE 1 : ARCHITECTURE MATÉRIELLE \& BACKEND SYSTÈME](#️-chapitre-1--architecture-matérielle--backend-système)
    - [1.1 Le Pont Série Physique (`/dev/ttyUSB0`)](#11-le-pont-série-physique-devttyusb0)
    - [1.2 La Séquence d'Initialisation au Clavier (Cold Boot)](#12-la-séquence-dinitialisation-au-clavier-cold-boot)
    - [1.3 Le Backend Linux (`stty` et lecture non-bloquante)](#13-le-backend-linux-stty-et-lecture-non-bloquante)
    - [1.4 Le Décodeur Matériel de Séquences (`M.get_key`)](#14-le-décodeur-matériel-de-séquences-mget_key)
  - [🎨 CHAPITRE 2 : LE MOTEUR GRAPHIQUE "DELTA-DRAWING" \& LE SDK (`minitel.lua`)](#-chapitre-2--le-moteur-graphique-delta-drawing--le-sdk-minitellua)
    - [2.1 Le Principe du "Delta-Drawing"](#21-le-principe-du-delta-drawing)
    - [2.2 Référence Complète des Fonctions du SDK (`minitel.lua`)](#22-référence-complète-des-fonctions-du-sdk-minitellua)
  - [🧭 CHAPITRE 3 : NAVIGATION GLOBALE \& PORTAILS DYNAMIQUES](#-chapitre-3--navigation-globale--portails-dynamiques)
    - [3.1 Le Portail Système Maître (`master.lua`)](#31-le-portail-système-maître-masterlua)
    - [3.2 Les Lanceurs à Détection Automatique (`launcher_jeux.lua` \& `launcher_utils.lua`)](#32-les-lanceurs-à-détection-automatique-launcher_jeuxlua--launcher_utilslua)
  - [🧰 CHAPITRE 4 : MANUEL DES LOGICIELS BUREAUTIQUES \& TÉLÉMATIQUES (`/utils`)](#-chapitre-4--manuel-des-logiciels-bureautiques--télématiques-utils)
    - [4.1 MAGIS EDIT (`utils/edit.lua`) — Traitement de Texte Plein Écran](#41-magis-edit-utilseditlua--traitement-de-texte-plein-écran)
    - [4.2 MAGIS CALC (`utils/calc.lua`) — Tableur Multi-Feuilles Dynamique](#42-magis-calc-utilscalclua--tableur-multi-feuilles-dynamique)
      - [Syntaxe des Formules (commençant par `=`)](#syntaxe-des-formules-commençant-par-)
    - [4.3 Les Utilitaires Télématiques en Direct (`train.lua`, `carburant.lua`, `updater.lua`)](#43-les-utilitaires-télématiques-en-direct-trainlua-carburantlua-updaterlua)
  - [💻 CHAPITRE 5 : LE LANGAGE MICRO-BASIC TÉLÉTEL V4.0 \& PROGRAMMES À TAPER](#-chapitre-5--le-langage-micro-basic-télétel-v40--programmes-à-taper)
    - [5.1 Référence Complète du Langage MICRO-BASIC](#51-référence-complète-du-langage-micro-basic)
    - [5.2 Cinq Programmes BASIC Complets à Taper ("Type-In Listings")](#52-cinq-programmes-basic-complets-à-taper-type-in-listings)
      - [🏆 PROGRAMME 1 : "LE NOMBRE MYSTÈRE" (Initiation, Boucles \& Conditions)](#-programme-1--le-nombre-mystère-initiation-boucles--conditions)
      - [🧱 PROGRAMME 2 : "BALLE REBONDISSANTE TEMPS RÉEL" (Animation `LOCATE` \& Physique)](#-programme-2--balle-rebondissante-temps-réel-animation-locate--physique)
      - [🏎️ PROGRAMME 3 : "SLALOM SUR LA NORDSCHLEIFE" (Jeu d'Arcade Complet au Clavier !)](#️-programme-3--slalom-sur-la-nordschleife-jeu-darcade-complet-au-clavier-)
      - [📈 PROGRAMME 4 : "TRACEUR DE COURBE SINUSOÏDALE \& COSINUS" (Mathématiques \& Graphisme)](#-programme-4--traceur-de-courbe-sinusoïdale--cosinus-mathématiques--graphisme)
      - [⚙️ PROGRAMME 5 : "BANC DE PUISSANCE \& COMPTE-TOURS" (Simulation Automobile)](#️-programme-5--banc-de-puissance--compte-tours-simulation-automobile)
  - [🕹️ CHAPITRE 6 : ENCYCLOPÉDIE DES JEUX \& LORE (`/jeux`)](#️-chapitre-6--encyclopédie-des-jeux--lore-jeux)
    - [6.1 RPG : ENIGMA (`jeux/minitel_rpg.lua`)](#61-rpg--enigma-jeuxminitel_rpglua)
    - [6.2 3615 BOURSE (`jeux/bourse.lua`)](#62-3615-bourse-jeuxbourselua)
    - [6.3 3615 ANOMALIE (`jeux/anomalie.lua`) \& 3615 POKER (`jeux/poker.lua`)](#63-3615-anomalie-jeuxanomalielua--3615-poker-jeuxpokerlua)
  - [🛠️ CHAPITRE 7 : GUIDE DU DÉVELOPPEUR — CRÉER UNE CARTOUCHE LUA](#️-chapitre-7--guide-du-développeur--créer-une-cartouche-lua)

---

## ⚙️ CHAPITRE 1 : ARCHITECTURE MATÉRIELLE & BACKEND SYSTÈME

Pour comprendre comment un terminal conçu dans les années 1980/1990 peut afficher des interfaces fenêtrées instantanées, calculer des feuilles de tableur ou interroger des serveurs gouvernementaux en HTTPS, il faut plonger sous le capot de l'architecture **Maître / Esclave** du projet `minitel_gc`.

```text
+-----------------------------------+          Câble Série DIN 5 Broches         +-----------------------------------+
|     TERMINAL MINITEL MAGIS        |                (UART / USB)                |       UNITE CENTRALE LINUX        |
|                                   | <========================================> |          (RASPBERRY PI)           |
| - Ecran CRT 80x24 (Mode VT100)    |          Flux Texte ANSI @ 9600 Bds        | - Service : serial-getty@ttyUSB0  |
| - Clavier Etendu (Codes Escape)   |                Format : 8N1                | - Moteur  : Lua 5.3 + minitel.lua |
| - Echo Local : DESACTIVE          |                                            | - Audio   : Synthetiseur SoX      |
+-----------------------------------+                                            +-----------------------------------+
```

### 1.1 Le Pont Série Physique (`/dev/ttyUSB0`)
Par défaut, à l'allumage, un Minitel démarre en mode **Vidéotex** (norme Télétel CEPT2) : l'écran affiche 40 colonnes sur 25 lignes, et le modem interne communique à 1200 bauds en réception et 75 bauds en émission (7 bits, parité paire).

Le projet `minitel_gc` exploite une fonction avancée des Minitel évolués (Magis Club, Minitel 2, Minitel 1B) : **le Mode Téléinformatique 80 colonnes (norme ANSI / DEC VT100)**.
* **La prise péri-informatique** située à l'arrière du Minitel est reliée au port USB du Raspberry Pi via un convertisseur série UART-TTL / USB (identifié sous Linux comme `/dev/ttyUSB0`).
* **Débit binaire (Baudrate)** : La vitesse est configurée à **9600 bauds** (soit environ **960 caractères transmis par seconde**), en format **8N1** (`cs8 -parenb -cstopb` : 8 bits de données, aucune parité, 1 bit d'arrêt).
* **Compatibilité PC de Développement** : Si `/dev/ttyUSB0` n'est pas détecté au lancement, `minitel.lua` bascule automatiquement en **Mode Émulation PC** sur le terminal standard de votre ordinateur Linux/macOS !

### 1.2 La Séquence d'Initialisation au Clavier (Cold Boot)
Lorsque vous allumez physiquement l'interrupteur du Minitel, celui-ci démarre en 40 colonnes. Le script maître (`master.lua`) affiche alors l'écran d'initialisation `"BOOT"` jusqu'à ce que l'opérateur bascule le terminal avec trois combinaisons de touches :

1. **`Ctrl + Esc` puis `T` puis `A` (Téléinformatique ASCII)** : Le processeur vidéo du Minitel bascule la résolution du tube cathodique de 40 à **80 colonnes** et active l'interpréteur ANSI/VT100.
2. **`Ctrl + Esc` puis `T` puis `E` (Téléinformatique Écho OFF)** : Désactive l'écho local du Minitel. Le clavier devient un périphérique d'entrée pur : chaque touche pressée est envoyée au Raspberry Pi sans polluer l'écran.
3. **`Ctrl + Esc` puis `C` puis `E` (Clavier Étendu)** : Active l'envoi des touches fléchées et des touches de fonction télématiques sous forme de séquences d'échappement VT100.

Dès que vous appuyez sur **`[ENVOI]`**, `master.lua` crée un fichier témoin en mémoire vive (`/tmp/minitel_warmboot`). Tant que le Raspberry Pi reste sous tension, le système reconnaît ce *Warm Boot* et affiche directement le portail principal.

### 1.3 Le Backend Linux (`stty` et lecture non-bloquante)
Dans `minitel.init()`, le SDK configure le pilote de terminal Linux avec la commande :
```bash
stty -F /dev/ttyUSB0 9600 cs8 -parenb -cstopb raw -echo -icanon min 0 time 0 2>/dev/null
```
* **`raw` & `-icanon`** : Désactive la mise en mémoire tampon ligne par ligne. Chaque octet envoyé par le Minitel arrive immédiatement dans le flux `io.read(1)` de Lua sans attendre la touche `Entrée`.
* **`min 0 time 0`** : Configure la lecture du port série en mode **100 % non-bloquant**. Si le joueur ne touche pas au clavier, `io.read(1)` renvoie instantanément `nil`. Cela permet à la boucle principale de faire tourner un écran de veille, une animation 3D ou une télémétrie tout en scrutant le clavier 100 fois par seconde (`minitel.sleep(0.01)`).

### 1.4 Le Décodeur Matériel de Séquences (`M.get_key`)
Appuyer sur une flèche ou une touche de fonction Minitel envoie une rafale de 3 ou 4 octets commençant par `\x1b` (`ESC`). À 9600 bauds, il s'écoule ~1 milliseconde entre chaque octet. La fonction `M.get_key()` intègre une boucle d'absorption matérielle (`read_next()`) de `50 000` cycles pour capturer la séquence complète et la traduire :

| Touche Physique Minitel / PC                       | Séquence Brute reçue (Hex / ASCII)        | Constante renvoyée par `M.get_key()`  |
| :------------------------------------------------- | :---------------------------------------- | :------------------------------------ |
| **Flèche HAUT / BAS / DROITE / GAUCHE**            | `\x1b[A` / `\x1b[B` / `\x1b[C` / `\x1b[D` | `"UP"`, `"DOWN"`, `"RIGHT"`, `"LEFT"` |
| **Touches Début / Fin**                            | `\x1b[H` / `\x1b[F`                       | `"HOME"`, `"END"`                     |
| **Touche `[ENVOI]`** *(ou Entrée PC)*              | `\x1bOM` *(ou `\r` / `\n`)*               | `"ENVOI"`                             |
| **Touche `[RETOUR]`** *(ou Échap / F3 PC)*         | `\x1bOR` *(ou `\x1b` seul)*               | `"RETOUR"` / `"ESC"`                  |
| **Touche `[CORRECTION]`** *(ou Backspace / Suppr)* | `\x1bOl` / `\x1b[3~` / `\x7f`             | `"CORRECTION"`                        |
| **Touche `[ANNULATION]`** *(ou F2 PC)*             | `\x1bOQ` / `\x1b[12~`                     | `"ANNULATION"`                        |
| **Touche `[SOMMAIRE]`** *(ou F1 PC)*               | `\x1bOP` / `\x1b[11~`                     | `"SOMMAIRE"`                          |
| **Touche `[REPETITION]`** *(ou F4 PC)*             | `\x1bOS` / `\x1b[14~`                     | `"REPETITION"`                        |
| **Touche `[GUIDE]`** / **`[SUITE]`**               | `\x1bOm` / `\x1bOn`                       | `"GUIDE"` / `"SUITE"`                 |

---

## 🎨 CHAPITRE 2 : LE MOTEUR GRAPHIQUE "DELTA-DRAWING" & LE SDK (`minitel.lua`)

### 2.1 Le Principe du "Delta-Drawing"
Un écran complet de 80x24 caractères pèse environ **2 500 octets** (séquences ANSI comprises), soit **2,5 secondes** de transmission à 9600 bauds. Pour garantir un affichage instantané et sans clignotement :
1. **Squelette Statique** : Les cadres (`+---+`), bandeaux et bordures ne sont envoyés qu'une seule fois à l'ouverture de l'écran.
2. **Mise à jour différentielle** : Lors d'un déplacement de curseur, seules l'ancienne ligne (remise en texte normal `\x1b[0m`) et la nouvelle ligne (passée en vidéo inverse `\x1b[7m`) sont réécrites via `\x1b[Y;XH`. Seulement ~90 octets sont transmis (0,08 seconde).

### 2.2 Référence Complète des Fonctions du SDK (`minitel.lua`)

| Fonction du SDK                 | Paramètres                 | Description Technique                                                                                        |
| :------------------------------ | :------------------------- | :----------------------------------------------------------------------------------------------------------- |
| **`minitel.init()`**            | *(Aucun)*                  | Configure `/dev/ttyUSB0` (ou le terminal PC) en mode `raw -echo` et masque le curseur.                       |
| **`minitel.cleanup()`**         | *(Aucun)*                  | Restaure les marges ANSI `\x1b[r`, réaffiche le curseur, efface l'écran et remet `stty sane`.                |
| **`minitel.sleep(sec)`**        | `seconds` (nombre)         | Pause active précise basée sur l'horloge processeur `os.clock()`.                                            |
| **`minitel.play_sound(fx)`**    | `"hit"`, `"win"`, `"lose"` | Lance le synthétiseur `play` (SoX) en tâche de fond (`&`) sans bloquer l'exécution Lua.                      |
| **`minitel.get_key()`**         | *(Aucun)*                  | Lit le clavier sans bloquer et retourne le nom de la touche ou `nil`.                                        |
| **`minitel.pad(str, len)`**     | `str`, `len`               | Tronque ou complète une chaîne à droite avec des espaces pour garantir une largeur fixe.                     |
| **`minitel.center(str, len)`**  | `str`, `len`               | Centre une chaîne de caractères dans une largeur de `len` colonnes.                                          |
| **`minitel.clean_accents(s)`**  | `str`                      | Convertit tous les caractères accentués UTF-8 (`é, è, à, ç, œ...`) en ASCII majuscule pur.                   |
| **`minitel.wrap(txt, w, l)`**   | `text`, `max_w`, `max_l`   | Découpe un long paragraphe mot par mot en un tableau de lignes calibrées.                                    |
| **`minitel.draw_window(...)`**  | `x, y, w, h, title`        | Dessine un cadre `+---+` aux coordonnées `(x,y)` avec bandeau de titre centré en vidéo inverse.              |
| **`minitel.progress_bar(...)`** | `x, y, w, cur, max, pct`   | Dessine une jauge graphique proportionnelle `[#####.....] 50%`.                                              |
| **`minitel.msg_box(...)`**      | `title, msg, sound`        | Ouvre une boîte d'alerte modale centrée et attend `[ENVOI]` ou `[RETOUR]`.                                   |
| **`minitel.confirm_box(...)`**  | `title, question`          | Ouvre une boîte de dialogue modale avec choix **`> [ OUI ] <`** / **`[ NON ]`**, retourne `true` ou `false`. |
| **`minitel.input_box(...)`**    | `title, prompt, def, max`  | Ouvre une fenêtre de saisie de texte gérant `[CORRECTION]`, `[ANNULATION]` (vider) et `[RETOUR]`.            |
| **`minitel.file_browser(...)`** | `mode, start_dir`          | Ouvre l'explorateur de fichiers système (`"OPEN"` ou `"SAVE"`) et retourne le chemin choisi.                 |

---

## 🧭 CHAPITRE 3 : NAVIGATION GLOBALE & PORTAILS DYNAMIQUES

### 3.1 Le Portail Système Maître (`master.lua`)
Point d'entrée du système, il présente une interface en double panneau (Split-Screen) avec télémétrie temps réel (Température CPU du Raspberry Pi, Uptime, état Internet et adresse IP locale rafraîchis toutes les 30 secondes sans clignotement) :

```text
+------------------------------------------------------------------------------+
|  [OS]          * * *  PORTAIL SYSTEME : MAGIS CLUB  * * *           9600 BDS |
+------------------------------------------------------------------------------+
| .----------------------------------.  .------------------------------------. |
| |       COMMANDES & MODULES        |  |     MONITEUR & APERCU SYSTEME      | |
| |----------------------------------|  |------------------------------------| |
| |[[ > 01. 3615 JEUX            < ]]|  |         .------------.             | |
| |     02. 3615 OUTILS              |  |         | [CARTOUCHE]|             | |
| |     03. MAGIS EDIT               |  |         |   .----.   |             | |
| |     04. MISE A JOUR GIT          |  |         |   | () |   |             | |
| |     05. CONFIG RESEAU            |  |         '---'----'---'             | |
| |     06. TERMINAL BASH            |  |------------------------------------| |
| |     07. REDEMARRAGE              |  | CIBLE : SALLE D'ARCADE             | |
| |     08. EXTINCTION               |  | TYPE  : DIVERTISSEMENT             | |
| |                                  |  | Accedez au catalogue de jeux du    | |
| |                                  |  | Magis Club : Casino, Rogue-like... | |
| |----------------------------------|  |------------------------------------| |
| |    CPU: 43.8 C  |  UP: 04h12m    |  | NET:[[ EN LIGNE ]] IP:192.168.1.25 | |
| '----------------------------------'  '------------------------------------' |
|  [Z/S] NAVIGUER   |   [ENVOI] VALIDER   |   [R] RECHERCHE LUA   |   [VEILLE] |
+------------------------------------------------------------------------------+
```

### 3.2 Les Lanceurs à Détection Automatique (`launcher_jeux.lua` & `launcher_utils.lua`)
À chaque lancement (ou en appuyant sur **`[R]`**), les deux lanceurs scannent les dossiers `/jeux` et `/utils`, ouvrent chaque fichier `.lua` et lisent ses **2 premières lignes** :
```lua
-- @GENRE: GESTION / SPECULATION
-- @DESC: Achetez et revendez des composants rares entre 6 villes en 30 jours.
```
Le lanceur extrait alors automatiquement la catégorie, la description, la taille en Ko, le nombre de lignes de code, et **choisit automatiquement le logo ASCII correspondant au genre** (Cartes pour *Casino/Poker*, Graphique boursier pour *Gestion/Bourse*, Donjon pour *Rogue-like/RPG*, Grille pour *Tableur*, Locomotive pour *Train*, Pompe pour *Carburant/Auto*, etc.).

---

## 🧰 CHAPITRE 4 : MANUEL DES LOGICIELS BUREAUTIQUES & TÉLÉMATIQUES (`/utils`)

---

### 4.1 MAGIS EDIT (`utils/edit.lua`) — Traitement de Texte Plein Écran

Éditeur de texte et de code source 80 colonnes utilisant le fenêtrage matériel `\x1b[3;24r` et l'explorateur de fichiers *Norton Commander*.

```text
+------------------------------------------------------------------------------+
| MAGIS EDIT                                     [RETOUR] MENU FICHIER         |
| FICHIER : COURRIER.TXT* | LIGNE : 005/018 | COL : 24                         |
+------------------------------------------------------------------------------+
| COMPAGNIE GENERALE DE TELEMATIQUE                                            |
| SERVICE TECHNIQUE - SECTEUR HAUTE-MARNE                                      |
|                                                                              |
| OBJET : RAPPORT DE CONNEXION 9600 BAUDS                                      |
| Le terminal fonctionne_parfaitement.                                         |
|                +---------------- MENU FICHIER ---------------+               |
|                |                                             |               |
|                |   [[ [1] ]] REPRENDRE L'EDITION             |               |
|                |   [[ [2] ]] NOUVEAU FICHIER                 |               |
|                |   [[ [3] ]] OUVRIR UN FICHIER...            |               |
|                |   [[ [4] ]] SAUVEGARDER SOUS...             |               |
|                |   [[ [9] ]] QUITTER MAGIS EDIT              |               |
|                +---------------------------------------------+               |
+------------------------------------------------------------------------------+
```

* **Flèches / `HOME` / `END`** : Déplacement libre du curseur dans le texte.
* **`[ENVOI]`** : Coupe la ligne à la position du curseur et insère un retour à la ligne.
* **`[CORRECTION]`** : Supprime le caractère à gauche (ou fusionne avec la ligne supérieure si placé en colonne 1).
* **`[ANNULATION]`** : Vide instantanément toute la ligne courante.
* **`[RETOUR]`** : Ouvre le menu fichier (Nouveau, Ouvrir via `file_browser`, Sauvegarder sous, Quitter).

---

### 4.2 MAGIS CALC (`utils/calc.lua`) — Tableur Multi-Feuilles Dynamique

Tableur financier supportant de multiples feuilles par classeur, les références croisées et l'évaluation mathématique temps réel.

```text
+------------------------------------------------------------------------------+
| MAGIS CALC | FICHIER: ATELIER.LUA*  | FEUILLE 1/2 : PIECES_AUTO              |
| [C5] =SOMME("C1:C4")                                                         |
|     | A         | B | C            | D | E | F |  |
| --- |
| 01  | TRIANGLE  | 2 | 110          |   |   |   |  |
| 02  | INJECTEUR | 4 | 480          |   |   |   |  |
| 03  | BOUGIES   | 4 | 45           |   |   |   |  |
| 04  | JOINT EGR | 1 | 15           |   |   |   |  |
| 05  | TOTAL HT  |   | [[     650]] |   |   |   |
| 06  | TOTAL TTC |   | 780.0        |   |   |   |  |
+------------------------------------------------------------------------------+
| [ENTREE] EDITER | [REPETITION] CALCULER | [< >] FEUILLES | [RETOUR] MENU     |
+------------------------------------------------------------------------------+
```

#### Syntaxe des Formules (commençant par `=`)
* **Opérations** : `=A1+B1`, `=B1*C1`, `=(A1+B1)/2`, `=A1^2`.
* **Somme d'une plage** : `=SOMME("C1:C4")` (additionne toutes les cases de C1 à C4).
* **Moyenne d'une plage** : `=MOYENNE("C1:C4")`.
* **Calcul entre plusieurs feuilles** : `=FEUIL1!C5 * 1.20` (récupère la valeur de la case `C5` de `FEUIL1` dans une autre feuille).
* **Fonctions scientifiques** : `=math.sqrt(A1)`, `=math.floor(A1)`, `=math.sin(A1)`, `=math.max(A1,B1)`.
* **Touches spéciales** : `<` et `>` pour changer de feuille, `[ANNULATION]` pour vider une cellule, `[REPETITION]` pour recalculer tout le classeur.

---

### 4.3 Les Utilitaires Télématiques en Direct (`train.lua`, `carburant.lua`, `updater.lua`)

```text
+------------------------------------------------------------------------------+
|                     3615 CARBURANT - CP 52300 (4 STATIONS)                   |
| +------------ COMPARATEUR DES PRIX DU JOUR (TRIE PAR GAZOLE) -------------+  |
| |  VILLE & ADRESSE                            | GAZOLE  |  SP98   | E10/95|  |
| +-------------------------------------------------------------------------+  |
| |>[[ JOINVILLE - AVENUE DE LA MARNE           | 1.649E  | 1.829E  | 1.749E]] |
| |    SAINT-DIZIER - ROUTE DE NANCY            | 1.652E  | 1.835E  | 1.752E   |
| |    CHAUMONT - FAUBOURG DU MOULIN            | 1.669E  | 1.849E  | 1.769E   |
| +-------------------------------------------------------------------------+  |
| [Z/S] NAVIGUER | [ENVOI] DETAILS | [N] NOUVEAU CP | [A]CTUALISER | [RETOUR]  |
+------------------------------------------------------------------------------+
```

* **`3615 TRAIN` (`utils/train.lua`)** : Panneau *Solari* des prochains départs SNCF en direct. Affiche l'heure, le terminus, le numéro de train (`TER`, `TGV`, `IC`), la **Voie** et les **Retards** éventuels.
* **`3615 CARBURANT` (`utils/carburant.lua`)** : Interroge en 100 % Lua le flux gouvernemental `data.economie.gouv.fr` par Code Postal, trie les stations par prix du Gazole croissant, et élargit automatiquement la recherche à tout le département si un village n'a pas de station.
* **`3615 MISE À JOUR` (`updater.lua`)** : Client Git complet avec sauvegarde automatique des programmes BASIC locaux et résolution interactive des conflits (`Reset`, `Commit & Push` au clavier Minitel, ou renommage `*_local.lua`).

---

## 💻 CHAPITRE 5 : LE LANGAGE MICRO-BASIC TÉLÉTEL V4.0 & PROGRAMMES À TAPER

L'interpréteur **`utils/basic.lua`** transforme le Minitel en micro-ordinateur 8-bits doté de commandes graphiques temps réel.

```text
+------------------------------------------------------------------------------+
| MICRO-BASIC TELETEL V4.0               [EXIT] OU [RETOUR] POUR QUITTER       |
| LIGNES : 008 | FICHIER : RADAR.BAS | TAPEZ 'HELP'                            |
+------------------------------------------------------------------------------+
| READY.                                                                       |
| > LIST                                                                       |
| 10 CLS                                                                       |
| 20 PRINT "SYSTEME MICRO-BASIC PRET"                                          |
| > RUN_                                                                       |
+------------------------------------------------------------------------------+
```

### 5.1 Référence Complète du Langage MICRO-BASIC

| Catégorie              | Instruction / Fonction                             | Description et Exemple                                                                             |
| :--------------------- | :------------------------------------------------- | :------------------------------------------------------------------------------------------------- |
| **Système (Shell)**    | `RUN`, `LIST`, `NEW`, `DIR`                        | Exécuter, lister le code, effacer la RAM, voir les fichiers `.bas`.                                |
| **Fichiers & Édition** | `SAVE "NOM"`, `LOAD "NOM"`, `EDIT X`               | Sauvegarder, charger depuis `utils/prog_basic/`, ou éditer la ligne `X`.                           |
| **Affichage**          | `PRINT`, `CLS`, `LOCATE X,Y`                       | Afficher texte/variables (`;` bloque le saut de ligne), effacer, placer le curseur `(1-80, 3-24)`. |
| **Attributs & Son**    | `INVERT`, `NORMAL`, `BEEP`, `PAUSE S`              | Activer/désactiver la vidéo inverse, émettre un bip, attendre `S` secondes.                        |
| **Clavier**            | `INPUT X`, `MKEY()`                                | Saisie bloquante (`INPUT`) ou lecture temps réel non-bloquante (`MKEY()`).                         |
| **Flux & Boucles**     | `GOTO X`, `GOSUB X`..`RETURN`                      | Saut direct ou appel de sous-routine avec retour.                                                  |
| **Structures**         | `IF..THEN..ELSE`, `FOR..TO..NEXT`, `WHILE..WEND`   | Conditions et boucles classiques.                                                                  |
| **Alias Minitel**      | `EQ` (`=`), `NEQ` (`<>`), `LT` (`<`), `GT` (`>`)   | Alias alphabétiques pour éviter les combinaisons de touches complexes.                             |
| **Maths**              | `RND(N)`, `SIN`, `COS`, `SQR`, `INT`, `ABS`, `MOD` | Nombre aléatoire de `1` à `N`, trigonométrie, racine, partie entière, modulo.                      |

> **Codes renvoyés par `MKEY()` :** `0` (Aucune touche), `200` (Haut/Z), `201` (Bas/S), `202` (Gauche/Q), `203` (Droite/D), `13` (`[ENVOI]`), `27` (`[RETOUR]`), ou le code ASCII de la touche pressée.

---

### 5.2 Cinq Programmes BASIC Complets à Taper ("Type-In Listings")

Lancez `3615 OUTILS` $\rightarrow$ `BASIC`, tapez **`NEW`**, puis saisissez l'un des listings ci-dessous ligne par ligne (ou rédigez-les directement dans `MAGIS EDIT` et enregistrez-les sous `utils/prog_basic/NOM.bas` !).

---

#### 🏆 PROGRAMME 1 : "LE NOMBRE MYSTÈRE" (Initiation, Boucles & Conditions)
*L'ordinateur tire un nombre secret entre 1 et 100. Vous devez le trouver en un minimum d'essais.*

```basic
10 CLS
20 INVERT
30 PRINT " === LE NOMBRE MYSTERE (1 A 100) === "
40 NORMAL
50 S = RND(100)
60 E = 0
70 PRINT "DEVINEZ LE CODE SECRET :"
80 INPUT X
90 E = E + 1
100 IF X = S THEN GOTO 140
110 IF X < S THEN PRINT "-> C'EST PLUS GRAND !"
120 IF X > S THEN PRINT "-> C'EST PLUS PETIT !"
130 GOTO 80
140 BEEP
150 INVERT
160 PRINT "BRAVO ! TROUVE EN " ; E ; " ESSAIS !"
170 NORMAL
180 END
```
*Tapez `SAVE "MYSTERE"` puis `RUN`.*

---

#### 🧱 PROGRAMME 2 : "BALLE REBONDISSANTE TEMPS RÉEL" (Animation `LOCATE` & Physique)
*Une démonstration fluide du moteur graphique : une balle rebondit contre les quatre parois de l'écran Minitel en émettant un bip à chaque impact. Appuyez sur `[RETOUR]` pour arrêter.*

```basic
10 CLS
20 X = 40
30 Y = 12
40 DX = 1
50 DY = 1
60 LOCATE 22, 3
70 INVERT
80 PRINT " DEMONSTRATION rebond ([RETOUR] = STOP) " ;
90 NORMAL
100 LOCATE X, Y
110 PRINT " " ;
120 X = X + DX
130 Y = Y + DY
140 IF X <= 2 THEN DX = 1
150 IF X <= 2 THEN BEEP
160 IF X >= 78 THEN DX = -1
170 IF X >= 78 THEN BEEP
180 IF Y <= 4 THEN DY = 1
190 IF Y <= 4 THEN BEEP
200 IF Y >= 23 THEN DY = -1
210 IF Y >= 23 THEN BEEP
220 LOCATE X, Y
230 INVERT
240 PRINT "O" ;
250 NORMAL
260 K = MKEY()
270 IF K = 27 THEN END
280 PAUSE 0.04
290 GOTO 100
```
*Tapez `SAVE "REBOND"` puis `RUN`.*

---

#### 🏎️ PROGRAMME 3 : "SLALOM SUR LA NORDSCHLEIFE" (Jeu d'Arcade Complet au Clavier !)
*Vous pilotez votre voiture `[^]` en bas de l'écran avec `GAUCHE` et `DROITE` (ou `Q` et `D`). La route sinue aléatoirement de gauche à droite et défile à toute vitesse ! Si vous touchez les glissières de sécurité `||`, c'est la sortie de piste.*

```basic
10 CLS
20 PX = 40
30 RX = 28
40 RW = 22
50 S = 0
60 D = RND(3) - 2
70 RX = RX + D
80 IF RX < 5 THEN RX = 5
90 IF RX > 50 THEN RX = 50
100 K = MKEY()
110 IF K = 27 THEN END
120 IF K = 202 THEN PX = PX - 2
130 IF K = 203 THEN PX = PX + 2
140 LOCATE RX, 23
150 PRINT "||" ;
160 LOCATE RX + RW, 23
170 PRINT "||"
180 LOCATE PX, 22
190 INVERT
200 PRINT "[^]" ;
210 NORMAL
220 IF PX <= RX + 1 THEN GOTO 260
230 IF PX >= RX + RW - 2 THEN GOTO 260
240 S = S + 1
250 PAUSE 0.06
255 GOTO 60
260 BEEP
270 LOCATE 28, 12
280 INVERT
290 PRINT " CRASH ! DISTANCE : " ; S ; " M "
300 NORMAL
310 END
```
*Tapez `SAVE "RALLYE"` puis `RUN`.*

---

#### 📈 PROGRAMME 4 : "TRACEUR DE COURBE SINUSOÏDALE & COSINUS" (Mathématiques & Graphisme)
*Utilise les fonctions trigonométriques du MICRO-BASIC pour tracer deux ondes entrelacées sur toute la largeur des 80 colonnes de l'écran.*

```basic
10 CLS
20 LOCATE 24, 3
30 INVERT
40 PRINT " OSCILLOSCOPE TELEMATIQUE 80 COL " ;
50 NORMAL
60 FOR X = 2 TO 78
70 LOCATE X, 14
80 PRINT "-" ;
90 NEXT X
100 FOR X = 2 TO 78
110 A = X / 6
120 Y = 14 - INT(SIN(A) * 8)
130 C = 14 - INT(COS(A) * 8)
140 LOCATE X, C
150 PRINT "." ;
160 LOCATE X, Y
170 INVERT
180 PRINT "*" ;
190 NORMAL
200 PAUSE 0.02
210 NEXT X
220 LOCATE 2, 23
230 BEEP
240 PRINT "TRACE TERMINE."
250 END
```
*Tapez `SAVE "OSCILLO"` puis `RUN`.*

---

#### ⚙️ PROGRAMME 5 : "BANC DE PUISSANCE & COMPTE-TOURS" (Simulation Automobile)
*Simule une montée en régime de 1 000 à 7 000 tr/min avec affichage d'un bargraphe dynamique en vidéo inverse et calcul de la puissance en chevaux selon le couple.*

```basic
10 CLS
20 LOCATE 20, 4
30 INVERT
40 PRINT " === BANC D'ESSAI MOTEUR MAGIS === "
50 NORMAL
60 PRINT ""
70 PRINT "COUPLE MOTEUR MOYEN (EN NM, EX: 240) :"
80 INPUT C
90 CLS
100 FOR R = 1000 TO 6500
110 K = MKEY()
120 IF K = 27 THEN END
130 P = INT((C * R) / 7024)
140 B = INT(R / 150)
150 LOCATE 5, 8
160 PRINT "REGIME : " ; R ; " TR/MIN   |   PUISSANCE : " ; P ; " CH   "
170 LOCATE 5, 10
180 INVERT
190 FOR I = 1 TO B
200 PRINT " " ;
210 NEXT I
220 NORMAL
230 R = R + 249
240 PAUSE 0.08
250 NEXT R
260 BEEP
270 LOCATE 5, 14
280 INVERT
290 PRINT " PUISSANCE MAX ATTEINTE : " ; P ; " CH A 6500 TR/MIN "
300 NORMAL
310 END
```
*Tapez `SAVE "DYNO"` puis `RUN`.*

---

## 🕹️ CHAPITRE 6 : ENCYCLOPÉDIE DES JEUX & LORE (`/jeux`)

---

### 6.1 RPG : ENIGMA (`jeux/minitel_rpg.lua`)

```text
+------------------------------------------------------------++----------------+
|############################################################||+--TELEMETRIE--+|
|####..........###################...........################|||ROOT LVL : 02 ||
|####....@.....###################.....+.....################|||NOEUD    : -03||
|####..........###################...........################|||PURGES   : 014||
|#########.###########################.######################|||OVERCLOCK: +2 ||
|#########.............................######################|||INT: 028/038  ||
|###################.########################################|||[#######...]  ||
|###################.#################..........#############|||EXP: 012/020  ||
|###################.......*..........#####>....#############|||[######....]  ||
|#####################################..........#############||+--COMMANDES---+|
|############################################################|||ZQSD : DEPLAC.||
+------------------------------------------------------------++----------------+
|+-------------------------------- LOGS SYSTEME ------------------------------+|
|| > PATCH DE CODE APPLIQUE (+ 18 INT).                                       ||
|+----------------------------------------------------------------------------+|
```

* **Le Lore** : En composant `3615 ENIGMA`, vous avez brisé un verrou cryptographique oublié sur le réseau Transpac. Votre conscience est aspirée dans un serveur infecté sous la forme du processus **`ROOT (@)`**.
* **Exploration & Symboles** : `@` (Vous), `#` (Paroi mémoire), `+` (Patch de soin : +15 à +25 INT), `*` (Cycle processeur : Overclocking permanent `OVC +1`), `>` (Passerelle vers le nœud inférieur).
* **Système de Combat** : Affrontez 6 classes de malwares (*Worm*, *Trojan*, *Malware*, *Ransomware*, *Daemon*, *Noyau Fantôme*) à l'aide de 4 contre-mesures : **`[ INJECTION ]`** (précise à 95 %), **`[ OVERLOAD ]`** (60 % de précision mais triple le bonus `OVC`), **`[ PATCHER ]`** (soin en combat) et **`[ ABORT ]`** (fuite et dispersion des menaces).

---

### 6.2 3615 BOURSE (`jeux/bourse.lua`)

```text
+------------------------------------------------------------------------------+
|              * * *  3615 BOURSE - SPECULATION & COMPOSANTS  * * *            |
| [[ VILLE : CHAUMONT              ]]                   [[ JOUR : 08 / 30 ]]   |
| +-- COURS DU MARCHE LOCAL ----------+  +-- PORTEFEUILLE & TELEMETRIE ------+ |
| | COMPOSANT          PRIX   T STK   |  | LIQUIDE  :        14250 F         | |
| |-----------------------------------|  | BANQUE   :         5000 F (+3%/J) | |
| |>[[ DISQUETTES 5.25   18 F v  50 ]]<|  | DETTE    :    0 F (SOLDEE)        | |
| |   MODEMS V.23       195 F +   -   |  | FORTUNE  :        26750 F         | |
| |   EPROM 27C256      310 F =  20   |  |-----------------------------------| |
| |   PROCESSEURS Z80  3450 F !   -   |  | COFFRE (070/100) :                | |
| |   BARRETTES 64KO   1400 F -   -   |  | [###################.......]  70% | |
| |-----------------------------------|  | ECHEANCE MISSION :                | |
| | PRIX ACHAT MOY: 22 F | MAX: 30    |  | [########........................]| |
| +-----------------------------------+  +-----------------------------------+ |
| +--------------------------------------------------------------------------+ |
| | FLASH : PENURIE : PROCESSEURS Z80 HORS DE PRIX !                         | |
| +--------------------------------------------------------------------------+ |
| [Z/S] CHOIX | [A]CHETER | [V]ENDRE | [T]RAJET | [B]ANQUE | [RETOUR] MENU     |
+------------------------------------------------------------------------------+
```

* **Le Lore** : Courtier sur le marché gris des composants électroniques à la fin des années 80, vous avez **30 jours** pour rembourser une dette initiale de **5 000 F** (+8 % d'intérêts par jour !) et faire fortune entre Paris, Chaumont, Reims, Lyon, Grenoble et Rennes.
* **Mécaniques** : Surveillez les indicateurs de pénurie (`!`, prix x3) et de déstockage (`v`, prix /3). Le calculateur suit votre **Prix d'Achat Moyen** et affiche votre marge nette avant chaque vente. Sauvegarde multi-slots incluse via `file_browser`.

---

### 6.3 3615 ANOMALIE (`jeux/anomalie.lua`) & 3615 POKER (`jeux/poker.lua`)
* **`3615 ANOMALIE`** : Fiction interactive dans la Station Relais du Secteur 4. Gérez votre intégrité physique, récoltez les objets clés (`BADGE`, `CLEF_CRYPTO`) pour débloquer des choix sans combat, et sauvegardez votre progression à tout moment avec **`[S]`**.
* **`3615 POKER`** : Poker fermé à 5 cartes contre l'IA du croupier avec un jeu de 36 cartes télématiques. Utilisez **`[M]`** pour saisir une mise libre, **`[G]`** pour ouvrir la table des gains, et tentez le Carré (`x8`) ou les 5 Identiques (`x16`).

---

## 🛠️ CHAPITRE 7 : GUIDE DU DÉVELOPPEUR — CRÉER UNE CARTOUCHE LUA

Pour ajouter un jeu ou un outil au système, créez simplement un fichier `.lua` dans `/jeux` ou `/utils` en plaçant les balises `-- @GENRE:` (ou `-- @TYPE:`) et `-- @DESC:` sur les **2 premières lignes** :

```lua
-- @GENRE: COURSE / AUTO
-- @DESC: Simulateur de chronometrage et telemetrie sur circuit.

local minitel = require("minitel")
minitel.init()

io.write("\x1b[2J\x1b[H")
minitel.draw_window(12, 4, 56, 12, "3615 CHRONO CIRCUIT")

local pilote = minitel.input_box("INSCRIPTION", "Nom du pilote :", "PILOTE_52", 16)
if pilote then
    minitel.progress_bar(18, 10, 44, 100, 100, true)
    minitel.msg_box("DEPART", "Bonne route sur la Nordschleife, " .. pilote .. " !", "win")
end

minitel.cleanup()
```

> **Astuce avancée (Logo sur-mesure) :** Si vous souhaitez qu'un programme affiche votre propre dessin ASCII de 5 lignes dans le lanceur au lieu du logo automatique lié au genre, ajoutez simplement les balises `-- @ART1:` à `-- @ART5:` dans l'en-tête de votre fichier Lua !