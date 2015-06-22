Flambda

Nous proposon de remplacer l'inlining de OCaml. De serieuse limitation
sont présentent dans Closure qui ne peuvent simplement se corriger.
En particulier il n'y a pas de manière d'inliner une fonction locale.
C'est cette restriction qui a guidé les principaux changements de
flambda par rapport à clambda.

## Representation

Essentiellement des lambda termes non typé avec clotures explicite.

Pas cps: il faut pouvoir aller vers le cmm et mach:
mach n'a pas de manière de représenter des sauts entre blocs qui ne
soit pas un appel de fonction.

Les points particuliers:

### Constructions Fset_of_closures Fclosure Fvariable_in_closure

Les clotures sont explicites.
On peut acceder au contenu des clotures de l'exterieur,
* Fclosure pour les fonctions
* Fvariable_in_closures pour les variables capturées

Il y a volontairement de la redondance dans ces constructions. Sans
cela, il y aurait des bugs difficilement identifiables. Cette
redondance introduit des contraintes pas forcement nescessaires (?),
qui seront levée au besoin (pas de duplication de fonction dans des
branches).

Un point important est la présence du champ cl_specialised_arg qui
sert à représenter statiquement des informations de flux de donnés.
Si un argument de la fonction est toujours aliasé à une variable,
cette information peut être stockée dans ce champ. Cela force aussi
la variable à être disponible dans le scope de la fonction.

### Utilise un type de variable différent

Pour des raisons pratique, il y a le type `Variable.t`. Ce sont des
variables completement qualifiées. Ça rends des choses plus facile à
tracer. Les seuls Ident.t qui restent sont les globales: la valeur
toplevel d'un module ou une exception prédéfinie.

le type Closure_id.t et Var_within_closure.t sont des alias abstraits
de Variable.t qui servent à acceder aux champs d'une cloture depuis
l'exterieur. Ils sont sépararé pour éviter des erreurs d'alpha
renomage.

### Sous langages

La traduction du lambda au flambda n'utilises pas toutes les constructions:
* set_of_closures, closures, variable_in_closure sont introduites par l'inlining
* fvariable est introduit par la préparation à l'export: la boucle de transformation
  travail sur une seule expression. La conversion hors du flambda est en 2 étapes.
** conversion du flambda vers une expression contenant le code d'initialisation du module
   + une liste de constantes.
** conversion de ce format intermediaire vers le clambda

### Plus de structured_constant

les structured_constant sont déconstruits en makeblock: Une seule
manière de les gérer. Le retour à clambda les retrouve.

### constructeur apply

Un seul constructeur apply pour le cas direct et indirect. Les appels
directs sont juste annotés avec l'identifiant unique de la seule
fonction qui atteint ce point.

Cette information est utilisée pour la conversion vers le clambda.
Cela veut dire qu'une dépendance est toujours conservée sur la
cloture appelée. Pour éviter de la charger inutilement, la conversion
vers le clambda reconnais quelques patterns courants où ce chargement
peut être évité. Dans des cas comme
```
let t = (f, f) in
(fst t) x
```
cela peut maintenir le tuple t vivant inutilement. En pratique ces cas
semblent assez rare pour que les quelques patterns simples de clambdagen
soient suffisants.

Il serait possible d'annoter avec un set de fonctions au lieu d'un
singleton. Ça pourrait servir par exemple à generer un meilleur call
si elles ont toute le même nombre d'arguments.

### Constructions non représentables/restrictions

... TODO ... remplir les descriptions:

* fonction avec plusieur clotures
* duplication de branche avec fonction
* fonctions locales sans pile
* partie de fonction partagée
* informations de retour des fonctions restreintes

# Inlining

Il y a deux moments pour inliner:
* avant la conversion de clotures:
  on a le droit d'inliner si tout l'environnement est bindé
* après: on a toujours le droit, mais il faut acceder à l'environnement explicitement.

Closure fait le 2nd. Et on le garde:
* C'est plus simple pour le cross module
* On contrôle ce qui finit dans les clotures: on ne risque pas de les faire trop grossir par surprise.

Par contre c'est un peu plus laborieux de manipuler des
fonctions. Comme c'est quelquechose qui a tendance à générer assez
facilement des erreurs un peu dure à suivre (on n'affiche pas
forcement tout de la cloture au debug, ça ferait beaucoup trop
d'informations dure à lire), il y a des check assez complets
(Flambdachecks) qui attrapent à peu près toutes les erreurs de
manipulation d'environement de fonction.

## Heuristique

L'heuristique d'inlining change completement par rapport à celle de closure qui était:
  Si une fonction est plus petite que la taille du call plus le paramètre `-inline` et
  qu'elle ne contient pas de définition de fonction et n'est pas récursive, alors elle
  est marquée comme à inliner. si a un appel, la fonction est connue et est marquée
  comme à inliner, alors elle l'est.

Les différences principales sont:
1) Le choit de l'inlining est fait au site d'appel
2) les fonctions locales n'empèchent pas leur parent d'être inlinée
3) les fonctions récursives peuvent être 'spécialisées'
4) les fonctions 'découvertent' après une première passe d'inlining peuvent aussi l'être

### Choit au site d'appel

Cela a une importance pour les fonctions qui bénéficient beaucoup des informations
sur leur contexte. Par exemple

```
let f b x =
  if b then
    x
  else
    big expression

let g x = f true x
```

Dans ce cas, il est très interessant d'inlininer f dans g, car on peut
retirer un saut conditionnel et le code sera probablement réduit. Si
le code avait été évalué à la déclaration, sa taille aurait probablement
été considérée trop grosse pour être înlinée, mais au site d'appel,
sa vraie taille finale peut être connue. De plus, l'on ne veut probablement
pas inliner systématiquement cette fonction, car si b est inconnu, ou faux
il y a peu à y gagner contre une grosse augmentation de la taille. Dans
Closure, cela n'était pas forcement très grave, car les chaines d'inlining
étaient coupées assez vites. Cela a entraîné une certaine habitude à compiler
avec `-inline 10000` qui n'a pas vraiment de sens raisonnable.

### Fonctions locales

Une fonction telle que

```
let f x =
  let g y = x + 1 in
  (g,g)
```

Ne peut pas être inliné par Closure à cause de la définition de `g`. C'est
le cas qui a justifié la majorité des changements dans la représentation
intermédiaire. La majorité des foncteurs rentrent dans ce cas.

### Fonction d'ordre supérieur

Dans un cas comme

```
let map_couple f (a, b) =
  f a, f b

let succ x = x + 1

let c = map_couple succ (1, 2)
```

L'appel de iter_couple peut ici être inliné. Dans ce cas `succ` peut
être inliné dans le corps de `map_couple`.

### Fonctions récursives

Les fonctions récursives peuvent être soit spécialisées soit inlinées.

#### Spécialisation

La spécialisation copie le code complet de la fonction au site d'appel
et propage certaines informations. Pour éviter de spécialiser du code
qui n'en profiteraient pas, cela n'est fait que quand l'on a pu
prouver que la fonction garde certains arguments constant et qu'il y a
des informations pertinentes pour ces arguments. Par exemple pour list iter

```
let rec iter f l =
  match l with
  | [] -> ()
  | h :: t ->
    f h;
    iter f t
```

L'argument f est constant. Cette information est détectée syntaxiquement.
(Par Flambdautils.unchanging_params_in_recursion)

```
let do_iter f =
  iter f [1;2;3]
```

Dans ce contexte, aucune information n'est connue sur f, iter ne peut donc
pas y être spécialisée.

```
let rec iter_swap f g l =
  match l with
  | [] -> ()
  | 0 :: t ->
    iter_swap g f l
  | h :: t ->
    f h;
    iter_swap f g t
```

Dans cette version f et g sont inversés dans la branche 0. Aucun paramètre
n'est considérée comme constant.

Ce serait potentiellement interessant dans certain cas de spécialiser une fonction
comme iter_swap, mais rien n'est fait pour cela pour l'instant.

Quand une fonction est spécialisée de cette manière, les arguments
constants pour lesquels il y a des informations sont ajoutés au champ
`cl_specialised_arg` de la cloture

#### Inlining

Dans certains cas, il est plus interessant de dérouler le code de la fonction
que de la spécialiser. Par exemple

```
List.map ((+) 1) [1]
```

Si cette fonction est inlinée, on peut se retouver directement avec `[2]`.


### Choix de l'heuristique

La decision d'inliner ou non une fonction dépend d'un certain nombre de paramêtres.

Voir heuristique.dot

Dans un cas où une fonction peut être inlinée (la fonction est connue
et appliquée au bon nombre d'arguments, et pas dans une fonction stub),

* Si la fonction est marquée avec l'attribut `stub` (du type `Flambda.function_declaration`)
  elle est inlinée.

* Si la fonction est syntaxiquement connue comme ne pouvant être
  appelée qu'à cet endroit elle est inlinée. Par exemple.

```ocaml
(fun x -> x + 1) 2
```

  Ce cas particulier serait en pratique supprimé par Simplif (sur le
  lambda), mais d'autres occurences peuvent apparaître en déplaçant
  des `let`.

* Si l'appel de fonction est à toplevel, avec des informations
  pertinentes pour tous les arguments, alors elle est inlinée

* sa taille est d'abord soustraite au quota, (controlé par le
  paramètre `-inline`). Si ce quota tombe sous 0, il n'y a pas
  d'inlining. Ce test est la uniquement pour limiter le coût de
  l'inlining, il ne devrait pas être utilisé pour controler
  l'agressivité.

* Sinon on peut potentiellement inliner la fonction. Il y a un
  traitement particulier pour les fonction récursives

** Si la fonction n'est pas récursive, alors on tente de l'inliner en
   empechant tout inlining à l'interieur (sauf les stubs) et on évalue
   le bénéfice.

*** Si le bénéfice est suffisant, la fonction est gardée inlinée et
    la boucle de transformation est relancée dessus.

*** Sinon on retente d'inliner la fonction normalement. Chaque sous
    fonction inlinée consome le quota d'inlining commun. Le résultat
    est gardé tel quel si le bénéfice est suffisant.

** Si la fonction est récursive

*** Si le quota d'unroll (qui commence à la valeur spécifiée par
    `-unroll`) est positif, alors un inlining non récursif est tenté.
    Si le résultat est suffisement bon, il est gardé le quota d'unroll
    est décrémenté, et la boucle de transformation relancée dessus.

*** Si le quotat est null ou l'unroll n'est pas bénéfique, alors la
    fonction est considérée pour la spécialisation.
    Si la fonction peut bénéficier d'une spécialisation alors celle-ci
    est faite, et le bénéfice est évaluée pour savoir si la version
    spécialisée est conservée.

* Sinon l'appel est gardé sous sa forme originale.

#### Inlining non récursif en 2 passes

L'inlining des fonctions non récursives est séparés en 2 tests pour le
rendre plus prédictible et assurer des propriétés de monotonies raisonnables.

Si l'inlining d'une fonction est suffisement bénéfique en lui même, cela
rentrera dans le cas du premier test. Par contre il peut arriver que cela ne
soit interessant que quand des informations sur des sous appels sont aussi
propagés. Par exemple:

```ocaml
let map_tuple f (x,y,z) = (f x, f y, f z)
let succ_tuple t = map_tuple succ t
```

`map_tuple` peut ne pas être suffisement interessant à
inliner suivant les paramètres de compilation, mais si la fonction `f` est
connue comme étant `succ` cela devient probablement très interessant.

Ce cas sera détecté par la deuxième passe. Le séparer en 2 passes
permet de s'assurer que décider d'inliner une fonction en profondeur
n'empèchera jamais la fonction la moins profonde d'être inlinée si
elle était suffisement bonne. Cela ne devrait pas arriver souvent: la
fonction de bénéfice est faite pour que si deux choix sont bons
indépendemment, alors les deux choix combinés sont bons aussi. Mais il
y a des fonctiosn qui peuvent être inlinées sans suivre la fonction de
bénéfice: les stubs (dont certains peuvent être annotés par
l'utilisateur). Ainsi on assure la propriété: augmenter les paramètres
de l'inlining ne peut faire que aumenter le nombre de fonctions
inlinées.

Aussi séparer la première passe permet de restructurer un peu le code
après l'avoir traversé (`Flambdasimplify.lift_lets`).

#### Bénéfice

Pour évaluer si une fonction est interessante à inliner, une simple
approximation de l'amélioration est calculée. Quand le code de la
fonction est transformé en propageant les information sur les
arguments, certaines transformations sont évaluées: les branches
supprimées, allocations, applications de fonctions et applications
de primitives supprimées sont comptées. Cela ne représente pas
directement la réductions des calculs éffectués à l'exécutions car
ces opérations peuvent être présentes dans des branches.

```ocaml
let f b x =
  if b then x + 1
  else x

let g b = f b 3
```

Dans ce cas inliner `f` dans `g` permet de retirer 1 primitive.

Dans le cas de branches, le code retiré n'est pas compté comme retiré
car il n'était pas exécuté de manière sûre.

```ocaml
let f b x =
  if b then x + 1
  else x

let g x = f false 3
```

Dans ce cas inliner `f` dans `g` permet de retirer 1 branchement
conditionnel, mais pas de primitive.

Néamoins, cela peut entraîner la suppression de code mort:

```ocaml
let f b x =
  let r = x + 1 in
  if b then r
  else x

let g x = f false 3
```

Ici inliner `f` permet aussi de supprimer la définition de `r` d'où
une primitive.

Au moment d'inliner une fonction, son bénéfice est évalué (l'importance
de chaque composante est controlable par les paramêtres `-inline-*-cost`).
Si `taille du code original` - (`taille du nouveau code` + `bénéfice`) est
inférieur ou égale à zero.

Mettre le paramètre '-inline-prim-cost' à `n` veut donc dire qu'on est
prêt à augmenter la taille du code de `n` (dans une unitée arbitraire
de taille de code) pour chaque primitive supprimée de l'exécution.

Cela veut dire que par exemple une configuration ou tous les arguments
`-inline-*-cost` sont à 0 et `-no-functor-heuristics` est présent,
quels que soient les autres arguments, une fonction ne pourra être
inlinées que si cela réduit la taille du code (ou que c'est un stub).

Le paramètre '-inline-call-cost' correspond globalement au paramètre
`-inline` de closure (à un facteur constant (8) pret).

##### Limitations

* Réduire les allocations peut avoir un effet assez bénéfique, ce qui
  justicie de compter les allocation séparément des autres primitives,
  mais ce n'est pas possible de facilement toutes les compter. Les
  principale limitations viennent du fait que certaines allocations
  sont potentiellement supprimées à postériori:
  ** Les blocs constants sont alloués statiquement (et clotures)
  ** Les nombres boxés peuvent être déboxés

  Ceci pourrait être amélioré (entre autre choses) si la gestion du boxing
  était faite au niveau du flambda.

* Toutes les primitives (non allocations) sont considérées avec le même coût,
  alors que certaines sont beaucoup plus cher que d'autres.

  Il pourrait y avoir une table des coût pour certaines primitives (en
  particuliers pour des external C pure)

* Le compte des améliorations est très local. Il est possible
  par exemple que la suppression d'une branche supprime du code mort,
  qui ne soit pas directement dans la fonction inlinée.

  ```ocaml
  let f b x y =
    if b
    then x
    else fst y

  let g x =
    let a = x + 1 in
    let b = (x,x) in
    f true a b
  ```

  Ici inliner `f` dans `g` va permetre de supprimer `b` et son
  allocation, mais cela ne peut être attribué à `f` car c'est hors de
  son scope. Il serait possible de maintenir des compteurs sur chaque
  variable pour savoir si une transformation rend une variable morte,
  mais cela alourdirait la transformation et raterais néamoins un
  certain nombre de cas.

* Besoin de pondérer avec l'espérance du nombre d'évaluation
  Pour l'instant, le fait d'être dans une boucle ou sous un branchement
  conditionnel n'a pas d'influence sur l'évaluation du bénéfice. C'est
  probablement un manque important.

* L'architecture de la passe rend naturel un ordre de recherche de
  potentiel inlining, mais dans certains cas, il pourrait être
  interessant d'évaluer le bénéfice d'inliner certaines fonctions dans
  un autre ordre. Il serait possible d'appliquer la passe en ne
  cherchant à inliner qu'une fonction particulière à un site d'appel
  pour évaluer completement son effet, mais cela aurait probablement
  un coût prohibitif. Ce serait imaginable pour des builds en temps
  peu limités

#### Justification de l'heuristique d'inline toplevel

Un appel de fonction est considérée comme à toplevel si il n'est pas
dans une déclaration de fonction, dans une branche de if ou match,
dans une boucle ou dans un handler d'exception ou d'exception
statique. C'est à dire si cet appel est exécutée exactement une fois
(à moins d'interruption avant).

De plus l'heuristique ne s'applique que si tous les arguments sont
statiquement connus et pourvus d'informations pertinentes, et que la
fonction n'est pas récursive.

Ces applications peuvent en général beaucoup bénéficier d'être
completement inlinées, car elles vont probablement générer des
constantes qui profiteront au reste du code. Par exemple inliner un
foncteur comme map va permettre à la fois de rendre toutes les
fonctions déclarée closes et globalement accessibles. Les appels à
ces fonctions pourront donc être des appels directs et dans certains
cas aussi inlinés (par exemple Map.S.equal qui peut beaucoup en
profiter)

Comme ces bénéfices ne sont pas locaux (ils peuvent même assez souvent
n'apparaître que dans une autre unitée de compilation), il faut prendre
le risque d'étendre du code potentiellement inutile. Cette heuristique
en pratique a l'air de plutôt bien correspondres aux utilisations
classiques des foncteurs. Elle a aussi l'avantage d'être assez prédictible.

Une option est présente pour la désactiver dans les cas où cela déroulerait
des applications trop agressivement (`-no-functor-heuristics`)

#### Détail du quota d'inlining (`-inline`)

Idéalement l'on voudrait pouvoir évaluer tous les choix possible
d'inlining pour garder ceux interessant, mais cela serait trop cher à
la compilation. Pour limiter cela, il y a une heuristique (simple)
pour tenter ce qui a le plus de chance d'être gardé et couper la recherche.

Au démarage la traversée commence avec un quota fixé
(`-inline`). Quand une fonction est considérée pour l'inlining (pas
pour celles forcées, telles que les stubs où quand l'heuristique de
foncteur s'applique), sa taille est soustraite au quota. Si ce quota
deviens négatif, plus aucune fonction ne peut être inlinée. Ce quota
est propagé en suivant le parcourt en profondeur de la traversée. Au
retour au premier choix, le quota est réinitialisé pour les fonctions
suivantes

```ocaml
let f g x =
  let a = g x in
  let b = g a in
  a + b

let h g x =
  let c = f g x in
  let d = f g 3 in
  c + d

let i x =
  h (( * ) 2) x
```

```ocaml
let i x =
  (* quota = original *)
  let x = x in
  let g = (( * ) 2) in
  (* quota = original - size(i) *)
  (* <- *)
  let c = f g x in
  let d = f g 3 in
  c + d
```

```ocaml
let i x =
  (* quota = original *)
  let x = x in
  let g = (( * ) 2) in
  (* quota = original - size(i) *)
  let x = x in
  let g = g in
  (* quota = original - size(i) - size(f) *)
  let c =
    (* <- *)
    let a = g x in
    let b = g a in
    a + b
  in
  let d = f g 3 in
  c + d
```

```ocaml
let i x =
  (* quota = original *)
  let x = x in
  let g = (( * ) 2) in
  (* quota = original - size(i) *)
  let x = x in
  let g = g in
  (* quota = original - size(i) - size(f) *)
  let c =
    let a = x * 2 in
    (* quota = original - size(i) - size(f) - size(g) *)
    (* <- *)
    let b = g a in
    a + b
  in
  let d = f g 3 in
  c + d
```

Si `original - size(i) - size(f) - size(g)` est négatif, alors la
traversée n'essaiera pas d'inliner le deuxième appel à `g` et `f`.

Supposons par exemple que le résultat de l'inlining du premier appel à
`f` ne soit pas suffisement bon. La recherche continuera alors dans
cet état.

```ocaml
let i x =
  (* quota = original *)
  let x = x in
  let g = (( * ) 2) in
  (* quota = original - size(i) *)
  let c = f g x in
  (* <- *)
  let d = f g 3 in
  c + d
```

Le dépliage se fera alors sur le second appel à `f` avec le quota
original. Celui la est appelé sur une constante, le résultat sera donc
probablement gardé.

##### Choix de la propagation du quota

La propagation se fait en suivant aproximativement l'ordre
d'évaluation car cela donne une priorité sur les premières fonctions.
Assez souvent, les fonctions suivantes bénéficient plus si des
informations précisent sont propagées sur leurs argument, ce qui est
plus probable si plus de fonctions exécutées avant sont inlinées.

#### Justification de stub

Certaines fonctions peuvent être marquée comme devant toujours être
inlinées, quelque soit le context. Les fonctions marqués ainsi sont
celles qui ont une forte probabilité d'améliorer le code. Cette
annotation existe parce que l'évaluation du bénéfice de l'inlining
n'est pas forcement suffisant pour toujours les considérer comme à
réduire. Les cas concernés sont:

* Pas assez de quota.
  Si le quota d'inlining est épuisé, les fonctions stub sont néamoins inlinées.

* Améliore le contexte.
  Si mettre dans son contexte la fonction stub n'améliore pas spécialement son
  code mais améliore le code autour, l'évaluation de bénéfice ne sait pas l'attribuer
  à cette fonction et ne peut donc pas choisir correctement de garder la version
  inlinée.
  Cela arrive typiquement quand le stub se contente de faire des acces à des champs
  ou n'utilise pas tous ses arguments

```ocaml
let f a b = a + b
let g (a, b) = f a b (* stub *)

let v = g (1, 2)
```

  Si `g` est inlinée le code final pourra être réécrit en `let v = f 1 2`. Cela
  a permis de supprimer l'allocation du tuple `(1, 2)`.

```ocaml
let f a b = a + b
let g a b = f a 1 (* stub *)

let h x =
  let b = x * 2 in
  g x b
```

  Dans ce cas, inliner `g` permet de supprimer la dépendence à `b`.

* Fonctions récursives.
  Il n'est pas possible forcement possible d'inliner entre fonctions
  mutuellement récursives, par contre c'est toujours possible avec
  les stub.

```ocaml
let rec tak_curried x y z =
  if x > y then
    tak(tak (x-1, y, z), tak (y-1, z, x), tak (z-1, x, y))
  else
    z
and tak (x, y, z) = (* stub *)
  tak_curried x y z
```

#### Origine des stubs

Les fonctions annotées comme stub sont celles générées dans un certain
nombre de cas. C'est en général utilisé pour changer l'ABI d'une
fonction.

* fonctions tuplifies

```ocaml
let f (x,y) = x + y
```
Réécrit en
```ocaml
let rec f (x,y) = internal_f x y (* stub *)
and internal_f x y = x + y
```

L'annotation des fonctions tuplifiées est faite par Translcore et la
fonction intermédiaire est générée dans Closure_conversion (il n'y a
pas d'annotation `Tupled` sur les fonction en flambda). Pour l'instant
les seules fonctions qui ne prennent qu'un tuple en argument et qui
est directement déconstruit dans l'argument. Il n'y a pas de raison de
se restreindre à ce cas là. Une passe faite plus tard pourrait
appliquer cette transformation à tout argument qui est un bloc
déconstruit dans la fonction qui ne s'échappe pas (pour ne pas risquer
d'avoir à le réallouer).

* argument inutilisés

Si un argument n'est pas utilisé par une
fonction, un stub l'ignorant est ajouté:

```ocaml
let rec specialised_map f l = match l with
  | [] -> []
  | h :: t -> succ h :: specialised_map f t
```

```ocaml
let rec specialised_map_internal l = match l with
  | [] -> []
  | h :: t ->
    succ h :: specialised_map dummy_value t
and specialised_map f l = specialised_map_internal l (* stub *)
```

* arguments optionnels par défault

l'optimisation des arguments optionnels avec une valeur par défault a
été porté sous forme de fonction stub

```ocaml
let add ?(v=1) n = n + v
```

```ocaml
let rec add ?(v=1) n = add_internal v n (* stub *)
and add_internal v n = n + v
```

La transformation est faite dans `Simplify.split_default_wrapper` sur
le lambda code (avant faite sur le lambda dans Closure) qui ajoute une
annotation la fonction. Dans Closure_conversion l'annotation est
convertie en annotation stub.

##### Note: Les application partielle ne génèrent pas des fonctions stub

Les applications partielles connues génèrent des fonctions intermédiaires
```ocaml
let f x y = x + y
let g = f 1
```
est Réécrit en
```ocaml
let f x y = x + y
let g = fun y -> f 1 y
```

mais la nouvelle fonction n'est pas annotée comme un stub.  Ce n'est
pas annoté parce que dans ce cas, nous voulons que `g` puisse être
spécialisé avec argument qui lui sont déjà passés. Dans ce cas par
exemple, l'inlining de `f` nous donnera.

```ocaml
let f x y = x + y
let g = fun y -> 1 + y
```

Cela n'aurait pas été possible si `g` était un stub, l'inlining y est
interdit.

#### Pas d'inlining dans les stubs

Il n'y a pas d'inlining possible à l'interieur des fonctions marquées
comme stub, y compris d'autre fonctions stub. Cela empèche que
l'annotation stub s'étende à du code sur lequel il n'est pas sensé
s'appliquer. Cela empèche aussi de boucler entre des fonctions stubs
mutuellement récursives.

## Optimisations réalisées durant l'inlining

... TODO ...

### Propagation de constante

... TODO ...

### Elimination de code mort local

... TODO ...

### Résolution d'alias local

... TODO ...

## Tentative de bytecode sur flambda

L'acces aux clotures depuis l'exterieur est problématique en bytecode.
On pourrait rajouter des instructions pour ça dans le bytecode. Mais
ce n'est pas représentable efficacement en javascript (la raison pour
laquelles des gens voudraient faire du bytecode après inlining).

