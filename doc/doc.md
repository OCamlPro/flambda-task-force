Flambda

Nous proposon de remplacer l'inlining de OCaml. De serieuse limitation
sont présentent dans Closure qui ne peuvent simplement se corriger.
En particulier il n'y a pas de manière d'inliner une fonction locale.
C'est cette restriction qui a guidé les principaux changements de
flambda par rapport à clambda.

== Representation

Essentiellement des lambda termes non typé avec clotures explicite.

Pas cps: il faut pouvoir aller vers le cmm et mach:
mach n'a pas de manière de représenter des sauts entre blocs qui ne
soit pas un appel de fonction.

Les points particuliers:

=== Constructions Fset_of_closures Fclosure Fvariable_in_closure

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

=== Utilise un type de variable différent

Pour des raisons pratique, il y a le type `Variable.t`. Ce sont des
variables completement qualifiées. Ça rends des choses plus facile à
tracer. Les seuls Ident.t qui restent sont les globales: la valeur
toplevel d'un module ou une exception prédéfinie.

le type Closure_id.t et Var_within_closure.t sont des alias abstraits
de Variable.t qui servent à acceder aux champs d'une cloture depuis
l'exterieur. Ils sont sépararé pour éviter des erreurs d'alpha
renomage.

=== Sous langages

La traduction du lambda au flambda n'utilises pas toutes les constructions:
* set_of_closures, closures, variable_in_closure sont introduites par l'inlining
* fvariable est introduit par la préparation à l'export: la boucle de transformation
  travail sur une seule expression. La conversion hors du flambda est en 2 étapes.
** conversion du flambda vers une expression contenant le code d'initialisation du module
   + une liste de constantes.
** conversion de ce format intermediaire vers le clambda

=== Plus de structured_constant

les structured_constant sont déconstruits en makeblock: Une seule
manière de les gérer. Le retour à clambda les retrouve.

=== constructeur apply

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

=== Constructions non représentables/restrictions

... TODO ... remplir les descriptions:

* fonction avec plusieur clotures
* duplication de branche avec fonction
* fonctions locales sans pile
* partie de fonction partagée
* informations de retour des fonctions restreintes

= Inlining

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

== Heuristique

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

=== Choit au site d'appel

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

=== Fonctions locales

Une fonction telle que

```
let f x =
  let g y = x + 1 in
  (g,g)
```

Ne peut pas être inliné par Closure à cause de la définition de `g`. C'est
le cas qui a justifié la majorité des changements dans la représentation
intermédiaire. La majorité des foncteurs rentrent dans ce cas.

== Tentative de bytecode sur flambda

L'acces aux clotures depuis l'exterieur est problématique en bytecode.
On pourrait rajouter des instructions pour ça dans le bytecode. Mais
ce n'est pas représentable efficacement en javascript (la raison pour
laquelles des gens voudraient faire du bytecode après inlining).

