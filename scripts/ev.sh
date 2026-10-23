# Registra un comando y su salida en evidencias/<archivo>.txt  —  uso: ev <archivo> <comando...>
ev() { local f="evidencias/$1.txt"; shift; { echo "\$ $*"; eval "$@" 2>&1; echo; } | tee -a "$f"; }
