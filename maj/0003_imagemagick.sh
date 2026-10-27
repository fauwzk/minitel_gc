#!/bin/bash
# Script de mise a jour : joue une seule fois, en root, par updater.lua.
#
# Installe ImageMagick, dont 3615 PHOTOS a besoin pour lire les photos.
# Il faut Internet : sans reseau, le script echoue et sera retente a la
# mise a jour suivante.
set -e
if command -v convert >/dev/null 2>&1 || command -v magick >/dev/null 2>&1; then
    echo "ImageMagick deja installe."
    exit 0
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q imagemagick
