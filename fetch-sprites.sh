#!/bin/sh
# Downloads the battle sprites into ./sprites for local use.
# They are Nintendo / The Pokemon Company artwork served by Pokemon Showdown and are NOT part of this repo.
set -e
cd "$(dirname "$0")"; mkdir -p sprites
get() { curl -sfL -o "sprites/$2" "https://play.pokemonshowdown.com/sprites/$1" && echo "ok $2"; }
get ani-back/charizard.gif ani-back_charizard.gif
get ani-back/pikachu.gif   ani-back_pikachu.gif
get ani/kyogre.gif         ani_kyogre.gif
get trainers/ash.png       trainer_ash.png
