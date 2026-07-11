#!/bin/sh

VARFILE="./templates.var"
if [ -z "$VARFILE"  ] || [ ! -f "$VARFILE" ]; then
    echo "No var file: $VARFILE"
    exit 1
fi

. "$VARFILE"

USE_VARS='\
$PREPARE_TEMPLATE_SERVER1 \
$PREPARE_TEMPLATE_SERVER2 \
$PREPARE_TEMPLATE_PORT1 \
$PREPARE_TEMPLATE_PORT2 \
$PREPARE_TEMPLATE_ROLES \
$PREPARE_TEMPLATE_PASSWORD \
'

find ./tpl -maxdepth 1 -type f | while read -r srcfile; do
    rm -f "$srcfile"
done

find ./tpl/prepare -maxdepth 1 -type f ! -name '*.sh' | while read -r srcfile; do
    fname="$(basename "$srcfile")"
    envsubst "$USE_VARS" < "$srcfile" > "./tpl/$fname"
done


