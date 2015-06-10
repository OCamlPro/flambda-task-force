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

== Heuristique

... TODO ...

== Tentative de bytecode sur flambda

L'acces aux clotures depuis l'exterieur est problématique en bytecode.
On pourrait rajouter des instructions pour ça dans le bytecode. Mais
ce n'est pas représentable efficacement en javascript (la raison pour
laquelles des gens voudraient faire du bytecode après inlining).

