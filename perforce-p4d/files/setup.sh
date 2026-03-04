#!/bin/bash

if [ ! -d "$P4ROOT/etc" ]; then
    echo >&2 "First time installation, copying configuration from /etc/perforce to $P4ROOT/etc and relinking"
    mkdir -p "$P4ROOT/etc"
    cp -r /etc/perforce/* "$P4ROOT/etc/"
else
    echo >&2 "Configuration directory already exists, skipping copy"
fi

mv /etc/perforce /etc/perforce.orig
ln -s "$P4ROOT/etc" /etc/perforce

if ! p4dctl list 2>/dev/null | grep -q "$NAME"; then
    echo "Configuring Perforce Server..."
    echo /opt/perforce/sbin/configure-p4d.sh "$NAME" -n -p "$P4PORT" -r "$P4ROOT" -u "$P4USER" -P ******** --case "$P4CASE" --unicode
    DEBUG=true MONOCHROME=true /opt/perforce/sbin/configure-p4d.sh "$NAME" -n -p "$P4PORT" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" --case "$P4CASE" --unicode
fi

echo p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
echo p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX

echo "Starting Perforce Server $NAME..."
p4dctl start -t p4d "$NAME"
