#!/bin/bash
# vim:sw=4:ts=4:et:
#-------------------------------------------------------------------------------
# Configuration script for P4 Server
# Copyright 2025, Perforce Software Inc. All rights reserved.
#
# Synopsis:
#
#    configure-p4d.sh [service-name] [options]
#
#    Where options are:
#
#    -n                     - Use the following flags in non-interactive mode
#    -p <P4PORT>            - Set P4 Server's address
#    -r <P4ROOT>            - Set P4 Server's root directory
#    -u <username>          - P4 super-user login name
#    -P <password>          - P4 super-user password
#    --unicode              - Enable unicode mode on server
#    --case              - Case-sensitivity (0=sensitive[default],1=insensitive)
#
#    Password is only needed on initial configuration when the super-user
#    account is created. If reconfiguring an existing Perforce Server, the
#    super-user name and password are left alone.
#
#    Unicode mode is disabled by default. Specify --unicode if you
#    want it. This will change in a future release.
#
#-------------------------------------------------------------------------------

trap reset_terminal INT TERM

#-------------------------------------------------------------------------------
# Global variables
#-------------------------------------------------------------------------------
MONOCHROME=true
DEBUG=true
P4DCTL_CFG_FILE=/etc/perforce/p4dctl.conf
P4DCTL_CFG_DIR="${P4DCTL_CFG_FILE}.d"
P4DCTL_TEMPLATE="$P4DCTL_CFG_DIR/p4d.template"

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
usage()
{
    cat <<EOS

Usage: configure-p4d.sh [service-name] [options]

    -n                   - Use the following flags in non-interactive mode
    -p <P4PORT>          - P4 Server's address
    -r <P4ROOT>          - P4 Server's root directory
    -u <username>        - P4 super-user login name
    -P <password>        - P4 super-user password
    --unicode            - Enable unicode mode on server
    --case               - Case-sensitivity (0=sensitive[default],1=insensitive)
    -h --help            - Display this help and exit

The service-name is the identifier by which p4dctl will refer to a particular
P4 Server instance on this machine. Additionally, this will be used to set the
P4 Server's serverid.

For further installation documentation, refer to the System Administrators
Guide and the environmental variable section of the Command Reference.  Details
such as the form and function of the P4PORT variable are described there.

http://www.perforce.com/perforce/doc.current/manuals/p4sag/chapter.install.html
http://www.perforce.com/perforce/doc.current/manuals/cmdref/envars.html

EOS
}

die()
{
    error "FATAL: $*" >&2
    exit 1
}

highlight()
{
    $MONOCHROME || echo -e "\033[32m$1\033[0m"
    $MONOCHROME && echo -e "$1" || true
}

highlightOn()
{
    $MONOCHROME || echo -e "\033[32m"
    $MONOCHROME && echo "" || true
}

highlightOff()
{
    $MONOCHROME || echo -e "\033[0m"
    $MONOCHROME && echo "" || true
}

errorOn()
{
    $MONOCHROME || echo -e "\033[31m"
    $MONOCHROME && echo "" || true
}

error()
{
    $MONOCHROME || echo -e "\033[31m$1\033[0m" >&2
    $MONOCHROME && echo -e "$1" >&2 || true
}

debug()
{
    $DEBUG || return 0
    $MONOCHROME || echo -e "\033[33m$1\033[0m" >&2
    $MONOCHROME && echo -e "$1" >&2 || true
}

# In case the user interrupts while being prompted for a password
reset_terminal()
{
    stty echo -echonl
    exit 1
}

# Prompt the user for information by showing a prompt string, and if the
# prompt is for a password also disabling echo on the terminal. Optionally
# calls a validation function to check if the response is OK.
#
# promptfor <VAR> <prompt> [<ispassword>] [<defaultvalue>] [<validationfunc>]
promptfor()
{
    local secure=false
        local check_func=true
        local default_value=""

        local var="$1"
        local prompt="$2"
        [ -n "$3" ] && secure=$3
        [ -n "$4" ] && default_value=$4
        [ -n "$5" ] && check_func=$5

        [ -n "$default_value" ] && prompt="$prompt [$default_value]"

        while true; do

            local pw=""
            ($secure && stty -echo echonl) || true

            read -r -p "$prompt: " pw
            stty echo -echonl || true

            [ -z "$pw" -a -n "$default_value" ] && pw=$default_value

            if $check_func "$pw"; then
                eval "$var=\"$pw\""
                break;
            fi
        done
        true
}

# Root user check
# If not root, escalate with sudo
ensure_root()
{
    if [ $EUID != 0 ]; then
        error "This script must run with root privileges. Attempting to sudo!"
        sudo -H "$SCRIPTPATH/$SCRIPT" "$@"
        exit $?
    else
        # If we are root from a previous sudo, we need to ensure that the home
        # directory in the environment is correct for the effective user
        if [ "$HOME" != "$(getent passwd "$EUID" | cut -d ":" -f 6 )" ]; then
            export HOME="$(getent passwd "$EUID" | cut -d ":" -f 6 )"
        fi
    fi
}


LAST_PASS=""

validate_password()
{
    local pw=$1
    if [ "$LAST_PASS" != "" ]; then
        if [ "$LAST_PASS" != "$pw" ]; then
             error "Passwords do not match."
             LAST_PASS=""
             return 1
        else
            LAST_PASS=""
            return 0
        fi
    fi
    if ! strong_password "$pw"; then
        errorOn
        cat <<!

Passwords must be strong. A strong password is at least 8 characters long,
and contains characters from at least two of the following character classes:
upper-case characters, lower-case characters and non-alphabetic characters.

!
        highlightOff
        return 1
    fi
    LAST_PASS="$pw"
    echo "Re-enter password."
    return 1
}

strong_password()
{
    local pw=$1
    local secure=false

    if [ ${#pw} -ge 8 ]; then
        # Test for two character classes
        if echo "$pw" | egrep '[[:upper:]]' | egrep '[[:lower:]]' >/dev/null ; then
            secure=true
        elif echo "$pw" | egrep '[[:upper:]]' | egrep '[^[:alpha:]]' > /dev/null; then
            secure=true
        elif echo "$pw" | egrep '[[:lower:]]' | egrep '[^[:alpha:]]' > /dev/null; then
            secure=true
        else
            error "ERROR: Password too simple"
        fi
    else
        [ -n "$pw" ] && error "ERROR: Password too short."
    fi
    $secure
}

validate_username()
{
    local user=$1
    if [ -z "$user" ]; then
        return 1
    fi

    if echo "$user" | egrep "^[0-9]+" > /dev/null ; then
        error "Usernames must not begin with numbers."
        return 1
    fi

    return 0
}

# Test if our P4PORT indicates we're using SSL
server_uses_ssl()
{
    [ "${P4PORT%%:*}" = ssl ]
}

# Test if our server is Unicode enabled
server_uses_unicode()
{
    debug "Running $P4 -C none -ztag info"
    $P4 -C none -ztag info | grep '^... unicode enabled' > /dev/null
}

# Establish trust relationship, if necessary, with a P4 server.
trust_server()
{
    if server_uses_ssl; then
        highlight "Establish trust relationship with SSL-enabled server..."
        debug "Running $P4 -C none trust -f -y"
        $P4 -C none trust -f -y || true
        local OUSER=$SUDO_USER
        if [ -z "$OUSER" ]; then
            OUSER=$(who am i | awk '{print $1}')
        fi
        if [ -z "$OUSER" ]; then
            OUSER="root"
        fi
        [ "$OUSER" == "root" ] && return 0
        local OHOME=$(getent passwd $OUSER | cut -d : -f6)
        local OGUID=$(getent passwd $OUSER | cut -d : -f4)
        local HOME=$OHOME
        local USER=$OUSER
        highlight "Also adding trust to calling user '$USER'."
        debug "Running $P4 -C none trust -f -y"
        $P4 -C none trust -f -y > /dev/null || true
        [ -e "$OHOME/.p4trust"  ] && chown $OUSER:$OGUID "$OHOME/.p4trust"
        [ -e "$OHOME/.p4enviro" ] && chown $OUSER:$OGUID "$OHOME/.p4enviro"
        true
    else
        true
    fi
}

#
# Checks whether or not the server already exists.
#
server_exists()
{
    debug "Running p4dctl list"
    if echo "$(p4dctl list -t p4d 2>/dev/null)" | awk '{print $3}' | grep "$1" > /dev/null ; then
        debug "Found server $1"
        return 0
    else
        debug "Did not find server $1"
        return 1
    fi
}

# Locate the config file for this server
server_config_file()
{
    debug "Looking for config file"
    local svr=$1
    for f in "$P4DCTL_CFG_FILE" "$P4DCTL_CFG_DIR"/*.conf; do
        if [ "$f" != "$P4DCTL_CFG_DIR"/\*.conf ] && \
            grep "^p4d[ \t]*\<$1\>" "$f" > /dev/null; then
            RET=$f
            return 0
        fi
    done
    RET="${P4DCTL_CFG_DIR}/${svr}.conf"
    return 0
}

# Create fresh config file from template
define_server()
{
    debug "Writing new config file from template"
    local svr=$1
    local cfg_file="${P4DCTL_CFG_DIR}/${svr}.conf"
    sed \
        -e "s#%NAME%#${svr}#g" \
        -e "s#%PORT%#${P4PORT}#g" \
        -e "s#%ROOT%#${P4ROOT}#g" \
        -e "s#Template ##g" \
        "$P4DCTL_TEMPLATE" > "$cfg_file"
}

# Load the environment from a server config
load_server_env()
{
    debug "Loading config into environment"
    local svr=$1

    eval "$(p4dctl env "$svr" P4ROOT P4PORT P4SSLDIR Execute Owner Umask 2> /dev/null)"
    if [ -z "$Umask" ]; then
        Umask=077
    fi
}

# Save current environment back to server config
save_server_env()
{
    debug "Saving environment into config"
    local mode=$1
    local cfg_file=$2

    if [ "$mode" = full ]; then
        sed \
            -e "s#^\([ \t]*\)P4ROOT\([ \t]*\)=.*#\1P4ROOT\2=\t$P4ROOT#" \
            -e "s#^\([ \t]*\)P4PORT\([ \t]*\)=.*#\1P4PORT\2=\t$P4PORT#" \
            -e "s#^\([ \t]*\)P4SSLDIR\([ \t]*\)=.*#\1P4SSLDIR\2=\t${P4SSLDIR:-ssl}#" \
            "$cfg_file" > "${cfg_file}.tmp"
        if grep P4USER "${cfg_file}.tmp" > /dev/null ; then
            sed -e "s#^\([ \t]*\)P4USER\([ \t]*\)=.*#\1P4USER\2=\t$P4USER#" \
                -i "${cfg_file}.tmp"
        else
            sed -e "s:^\([ \t]*\)P4ROOT\([ \t]*\)=\(.*\):\P4ROOT\2=\3\n\1P4USER\2=\t$P4USER:" \
                -i "$cfg_file.tmp"
        fi
        if $AUTOUPGRADE; then
            sed -e "s:^\([ \t]*\)P4ROOT\([ \t]*\)=\(.*\):\P4ROOT\2=\3\n\1AUTOUPGRADE\2=\t1:" \
                -i "$cfg_file.tmp"
        fi
    else
        sed \
            -e "s#^\([ \t]*\)P4PORT\([ \t]*\)=.*#\1P4PORT\2=\t$P4PORT#" \
            "$cfg_file" > "${cfg_file}.tmp"
    fi
    mv -f "$cfg_file.tmp" "$cfg_file"
    load_server_env "$NAME"
}

#
# Checks whether or not the server already exists. We do this by searching
# the protections table for the definition of a super-user.
#
server_initialized()
{
    debug "Checking if server is already initialized"
    local svr=$1
    local r=false

    debug "Vars: P4ROOT=$P4ROOT Owner=$Owner Execute=$Execute Umask=$Umask"
    if [ -n "$P4ROOT" \
        -a -n "$Owner" \
        -a -n "$Execute" \
        -a -n "$Umask" \
        -a -d "$P4ROOT" \
        -a -f "$P4ROOT/db.counters"  \
        -a -x "$Execute" ]; then
        debug "P4ROOT exists"
        if id "$Owner" > /dev/null && \
           su "$Owner" -s /bin/sh -c "umask $Umask; $Execute -r $P4ROOT -jd - db.protect | grep ' 255 ' > /dev/null"; then
            r=true
        fi
    fi

    if $r; then
        debug "Server is initialized"
        return 0
    else
        debug "Server not initialized"
        return 1
    fi
}

#
# Generate SSL keys if required
#
gen_ssl_keys()
{
    debug "Generating new SSL key pair"
    local svr=$1

    debug "P4ROOT=$P4ROOT P4SSLDIR=$P4SSLDIR Owner=$Owner Execute=$Execute"
    if [ -n "$P4ROOT" \
        -a -n "$P4SSLDIR" \
        -a -n "$Owner" \
        -a -n "$Execute" \
        -a -x "$Execute" ] &&
        id "$Owner" > /dev/null; then

        # P4SSLDIR may be relative to P4ROOT
        pushd "$P4ROOT" >/dev/null
        if [ ! -d "$P4SSLDIR" ]; then
            mkdir -p "$P4SSLDIR"
        fi

        if [ ! -f "$P4SSLDIR/certificate.txt" \
            -a ! -f "$P4SSLDIR/privatekey.txt" ]; then
            debug "Running su $Owner -s /bin/sh -c \"P4SSLDIR=$P4SSLDIR $Execute -r $P4ROOT -Gc\""
            su "$Owner" -s /bin/sh -c "P4SSLDIR=$P4SSLDIR $Execute -r $P4ROOT -Gc"
        else
            highlight "SSL certificates found in $P4SSLDIR"
        fi
        popd >/dev/null
    else
        error "Can't create SSL certificates for server"
        false
    fi
}

#
# Prompt the user for P4 connection details. Only in interactive mode
#
fetch_p4_details()
{
    local svr=$1
    if $FRESH_INSTALL; then

        promptfor P4ROOT "P4 Server root (P4ROOT)" false "$P4ROOT" prompt_mkdir
        promptfor UNICODE "{P4} Server unicode-mode (y/n)" false "$UNICODE" check_bool_response
        promptfor CASE "P4 Server case-sensitive (y/n)" false "$CASE" check_bool_response
        promptfor P4PORT "P4 Server address (P4PORT)" false "$P4PORT" check_p4port
        promptfor P4USER "P4 super-user login" false "$P4USER" validate_username
        promptfor P4PASSWD "P4 super-user password" true "" validate_password

        if [ "$CASE" = y -o "$CASE" = Y -o "$CASE" = yes -o "$CASE" = true -o "$CASE" = 0 ]; then
            CASE=0
        else
            CASE=1
        fi
    else
        promptfor P4PORT "P4 Server address (P4PORT)" false "$P4PORT"
    fi
}

# Validate that we have all we need
check_p4_details()
{
    local svr=$1

    if $FRESH_INSTALL; then
        [ -z "$P4ROOT" ]            && return 1
        [ -z "$P4PORT" ]            && return 1
        [ -z "$P4USER"  ]           && return 1
        [ -z "$P4PASSWD"  ]         && return 1
        if ! strong_password "$P4PASSWD"; then
            P4PASSWD=
            return 1
        fi
        if ! validate_username "$P4USER"; then
            P4USER=
            return 1
        fi
        if ! check_p4port "$P4PORT"; then
            P4PORT=
            return 1
        fi
        return 0
    else
        # Server already configured. We may wish to change the port,
        # but that's all that's permitted.
        [ -z "$P4PORT" ]            && return 1
        if ! check_p4port "$P4PORT"; then
            P4PORT=
            return 1
        fi
    fi
    return 0
}

#
# Check that a directory exists and if not, prompt the user to create it
#
prompt_mkdir()
{
    dir=$1
    [ -d "$dir" ] && return 0

    local answer
    promptfor answer "Create directory? (y/n)" false y check_bool_response
    if [ "$answer" = y -o "$answer" = Y -o "$answer" = yes -o "$answer" = true -o "$answer" = 0 ]; then
        mkdir -p "$dir"
        chown -R perforce:perforce "$dir"
        chmod -R o=,g= "$dir"
    else
        return 1
    fi
    return 0
}

#
# Checks whether or not the port is used by P4DCTL
#
p4dctl_has_port()
{
    p4dctl list 2> /dev/null | grep "port=[^ ]*$(echo "$1" | sed -e 's/.*://')" > /dev/null
}

#
# Checks whether or not the port is in use.
#
port_in_use()
{
    netstat -ltn | awk '{print $4}' | grep "$(echo "$1" | sed -e 's/.*://')" > /dev/null
}

check_not_empty()
{
    if [ -z "$1" ]; then
        return 1
    fi
    return 0
}

check_p4port()
{
    local port=$1

    if [ -z "$port" ]; then
        return 1
    fi

    # See if they want SSL or not.
    if [ "$port#ssl" = "$port" ]; then
        SSL=false
    else
        SSL=true
    fi

    local protos="tcp tcp4 tcp6 tcp46 tcp64 ssl ssl4 ssl6 ssl46 ssl64"
    local proto=""
    local host=""
    local pnum=""

    # Check the format of P4PORT
    local bits=(${port//:/ })
    local count=${#bits[@]}
    if [ $count -eq 1 ]; then
        pnum=${bits[0]}
    elif [ $count -eq 2 ]; then
        [[ $protos =~ ${bits[0]} ]] && proto=${bits[0]} || host=${bits[0]}
        pnum=${bits[1]}
    elif [ $count -eq 3 ]; then
        proto=${bits[0]}
        host=${bits[1]}
        pnum=${bits[2]}
    elif [ $count -gt 3 ]; then
        error "Too many parts in P4PORT: $port"
    fi

    # Check for protocol (does it match our list of valid protocols?)
    if [ -n "$proto" ] && [[ ! $protos =~ $proto ]]; then
        $hideErrors || error "Invalide P4 protocol: $PROTO"
        return 1
    fi

    # Check port range (port > 1020 && port =< 65535)
    local numre="^[0-9]+$"
    if [[ ! $pnum =~ $numre ]] || [ $pnum -le 1024 -o $pnum -gt 65535 ]; then
        error "Port number out of range (1025-65535): $pnum"
        return 1
    fi

    # If we're reconfiguring a service and not changing the port, skip the rest
    if echo $(p4dctl env $NAME P4PORT 2>/dev/null) | grep ":$pnum$"; then
        return 0
    fi

    # Check P4DCTL doesn't have another service configured on this port
    if p4dctl_has_port "$port" ; then
        error "P4PORT is already in use by another P4DCTL service."
        return 1
    fi

    # Check nothing else is listening on this port
    if port_in_use "$port" ; then
        error "P4PORT port number is already in use."
        return 1
    fi

    return 0
}

#
# Check a boolean Y/N response from the user
check_bool_response()
{
    r=$1
    [ "$r" = y -o "$r" = Y -o "$r" = yes -o "$r" = true  -o "$r" = 0 ] && return 0
    [ "$r" = n -o "$r" = N -o "$r" = no  -o "$r" = false -o "$r" = 1 ] && return 0
    return 1
}


#
# Initialize db files on a specified server.  Sets case-sensitivity.
#
initialize_db()
{
    local svr=$1

    [ -n "$P4ROOT" \
        -a -n "$P4PORT" \
        -a -n "$NAME" \
        -a -n "$Owner" \
        -a -n "$Execute" \
        -a -n "$Umask" \
        -a -d "$P4ROOT" \
        -a -d "$P4ROOT/../journals" \
        -a -d "$P4ROOT/../logs" \
        -a -x "$Execute" ] && \
        id "$Owner" >/dev/null 2>&1 && \
        su "$Owner" -s /bin/sh -c \
            "umask $Umask; $Execute -r \"$P4ROOT\" -C $CASE -L ../logs/log -J ../journals/journal \"-cset P4JOURNAL=../journals/journal\" > /dev/null" && \
        su "$Owner" -s /bin/sh -c \
            "umask $Umask; $Execute -r \"$P4ROOT\" -C $CASE -L ../logs/log -J ../journals/journal \"-cset P4LOG=../logs/log\" > /dev/null" && \
        su "$Owner" -s /bin/sh -c \
            "umask $Umask; $Execute -r \"$P4ROOT\" -C $CASE -L ../logs/log -J ../journals/journal \"-cset $NAME#P4PORT=$P4PORT\" > /dev/null" && \
        su "$Owner" -s /bin/sh -c \
            "umask $Umask; echo $NAME > $P4ROOT/server.id"
}

#
# Enable unicode mode on a specified server
#
enable_unicode()
{
    local svr=$1

    [ -n "$P4ROOT" \
        -a -n "$Owner" \
        -a -n "$Execute" \
        -a -n "$Umask" \
        -a -d "$P4ROOT" \
        -a -x "$Execute" ] && \
        id "$Owner" >/dev/null 2>&1 && \
        su "$Owner" -s /bin/sh -c "umask $Umask; $Execute -r \"$P4ROOT\" -xi"
}

initialize_repository()
{
    local svr=$1

    if $SSL; then
        trust_server
    fi

    if server_uses_unicode; then
        P4="$P4 -C utf8"
    else
        P4="$P4 -C none"
    fi
    highlight "Creating super-user account..."
    debug "Running $P4 user"
    $P4 user -o | $P4 user -i
    debug "$($P4 serverid)"

    debug "Setting configurables"
    $P4 configure set run.users.authorize=1 > /dev/null 2>&1 || true
    $P4 configure set dm.user.noautocreate=2 > /dev/null 2>&1 || true
    $P4 configure set dm.user.resetpassword=1 > /dev/null 2>&1 || true
    $P4 configure set dm.info.hide=1 > /dev/null 2>&1 || true
    $P4 configure set dm.user.hideinvalid=1 > /dev/null 2>&1 || true
    $P4 configure set server.start.unlicensed=1 > /dev/null 2>&1 || true

    $P4 configure set server.maxcommands=2500 > /dev/null 2>&1 || true
    $P4 configure set net.backlog=2048 > /dev/null 2>&1 || true
    $P4 configure set net.autotune=1 > /dev/null 2>&1 || true
    $P4 configure set db.monitor.shared=4096 > /dev/null 2>&1 || true
    $P4 configure set db.reorg.disable=1 > /dev/null 2>&1 || true
    $P4 configure set lbr.autocompress=1 > /dev/null 2>&1 || true

    $P4 configure set filesys.bufsize=1M > /dev/null 2>&1 || true
    $P4 configure set filesys.checklinks=2 > /dev/null 2>&1 || true
    $P4 configure set server.commandlimits=2 > /dev/null 2>&1 || true
    $P4 configure set "rejectList=P4EXP,version=2014.2" > /dev/null 2>&1 || true

    $P4 configure set rpl.checksum.auto=1 > /dev/null 2>&1 || true
    $P4 configure set rpl.checksum.change=2 > /dev/null 2>&1 || true
    $P4 configure set rpl.checksum.table=1 > /dev/null 2>&1 || true

    $P4 configure set proxy.monitor.level=1 > /dev/null 2>&1 || true
    $P4 configure set monitor=1 > /dev/null 2>&1 || true
    $P4 configure set server=3 > /dev/null 2>&1 || true

    $P4 configure set filesys.P4ROOT.min=2G > /dev/null 2>&1 || true
    $P4 configure set filesys.depot.min=2G > /dev/null 2>&1 || true
    $P4 configure set filesys.P4JOURNAL.min=2G > /dev/null 2>&1 || true
    $P4 configure set server.depot.root=../archives > /dev/null 2>&1 || true
    $P4 configure set journalPrefix=../journals/${NAME} > /dev/null 2>&1 || true

    debug "Enabling structured logs"
    $P4 configure set serverlog.file.1=../logs/commands.csv > /dev/null 2>&1 || true
    $P4 configure set serverlog.retain.1=10 > /dev/null 2>&1 || true
    $P4 configure set serverlog.file.2=../logs/errors.csv > /dev/null 2>&1 || true
    $P4 configure set serverlog.retain.2=10 > /dev/null 2>&1 || true
    $P4 configure set serverlog.file.3=../logs/events.csv > /dev/null 2>&1 || true
    $P4 configure set serverlog.retain.3=10 > /dev/null 2>&1 || true
    $P4 configure set serverlog.file.4=../logs/integrity.csv > /dev/null 2>&1 || true
    $P4 configure set serverlog.retain.4=10 > /dev/null 2>&1 || true
    $P4 configure set serverlog.file.5=../logs/auth.csv > /dev/null 2>&1 || true
    $P4 configure set serverlog.retain.5=10 > /dev/null 2>&1 || true

    debug "Enabling unload and spec depots"
    $P4 depot -o -t spec spec     | $P4 depot -i > /dev/null
    $P4 admin updatespecdepot -a > /dev/null
    $P4 depot -o -t unload unload | $P4 depot -i > /dev/null

    debug "Moving P4PORT to server spec"
    $P4 server -i > /dev/null <<!
ServerID: $NAME
Type: server
Services: commit-server
Address: $P4PORT
Description: Created configure-helix-p4d.sh
!
    if $P4 server -o $NAME | grep "^Address:\s*$P4PORT$" > /dev/null; then
        $P4 configure unset "$NAME#P4PORT" > /dev/null
    fi

    debug "Populating the typemap"
    $P4 typemap -i > /dev/null <<!
TypeMap:
        text //....asp
        text //....cnf
        text //....css
        text //....htm
        text //....html
        text //....inc
        text //....js
        text+w //....log
        text+w //....ini
        text+w //....pdm
        binary+Fl //....zip
        binary+Fl //....bz2
        binary+Fl //....rar
        binary+Fl //....gz
        binary+Fl //....avi
        binary+Fl //....jpg
        binary+Fl //....jpeg
        binary+Fl //....mpg
        binary+Fl //....gif
        binary+Fl //....tif
        binary+Fl //....mov
        binary+Fl //....jar
        binary+l //....ico
        binary+l //....exp
        binary+l //....btr
        binary+l //....bmp
        binary+l //....doc
        binary+l //....dot
        binary+l //....xls
        binary+l //....ppt
        binary+l //....pdf
        binary+l //....tar
        binary+l //....exe
        binary+l //....dll
        binary+l //....lib
        binary+l //....bin
        binary+l //....class
        binary+l //....war
        binary+l //....ear
        binary+l //....so
        binary+l //....rpt
        binary+l //....cfm
        binary+l //....ma
        binary+l //....mb
        binary+l //....pac
        binary+l //....m4a
        binary+l //....mp4
        binary+l //....aac
        binary+l //....wma
        binary+l //....docx
        binary+l //....pptx
        binary+l //....xlsx
        binary+l //....png
        binary+l //....raw
        binary+l //....odt
        binary+l //....ods
        binary+l //....odg
        binary+l //....odp
        binary+l //....otg
        binary+l //....ots
        binary+l //....ott
        binary+l //....psd
        binary+l //....sxw
!

    highlight "Initializing protections table..."
    debug "Running $P4 protect"
    $P4 protect -o | sed -e "/write user/a \\\\tlist user * * -//spec/..." | $P4 protect -i
    highlight "Setting security level to 4 (high)..."
    debug "Running $P4 counter -f security 4"
    $P4 counter -f security 4
    highlight "Setting password..."
    debug "Running $P4 passwd"
    $P4 passwd > /dev/null <<!
$P4PASSWD
$P4PASSWD
!

    highlight "Creating ticket for root user"
    debug "Running $P4 login"
    $P4 login > /dev/null <<!
$P4PASSWD
!
    debug "Confurables setup complete"
    debug "$($P4 configure show)"

    [ -z "$($P4 set P4USER)" ] && $P4 set P4USER=$P4USER
    [ -z "$($P4 set P4PORT)" ] && $P4 set P4PORT=$P4PORT

    local OUSER=$SUDO_USER
    if [ -z "$OUSER" ]; then
        OUSER=$(who am i | awk '{print $1}')
    fi
    if [ -z "$OUSER" ]; then
        OUSER="root"
    fi
    [ "$OUSER" == "root" ] && return 0
    local OHOME=$(getent passwd $OUSER | cut -d : -f6)
    local OGUID=$(getent passwd $OUSER | cut -d : -f4)
    local HOME=$OHOME
    local USER=$OUSER
    highlight "Also creating ticket for calling user '$USER'."
    debug "Running (as $USER) $P4 login"
    [ -e "$OHOME/.p4tickets" ] && chown $OUSER:$OGUID "$OHOME/.p4tickets"
    [ -e "$OHOME/.p4enviro"  ] && chown $OUSER:$OGUID "$OHOME/.p4enviro"
    su - $USER -s /bin/bash -c "echo $P4PASSWD| $P4 login > /dev/null"
    [ -z "$($P4 set P4USER)" ] && su - $USER -s /bin/bash -c "$P4 set P4USER=$P4USER"
    [ -z "$($P4 set P4PORT)" ] && su - $USER -s /bin/bash -c "$P4 set P4PORT=$P4PORT"
    true
}

#
# Initialize a fresh P4 server. If it already exists, we do nothing.
#
configure_server()
{
    local svr=$1
    local cfg=$2

    # OK, now we know we need to configure this server.
    if $FRESH_INSTALL; then
        define_server "$NAME"
        # P4SSLDIR lives under P4ROOT. Like it or not.
        P4SSLDIR=ssl
        [ ! -d "$P4ROOT" ]          && mkdir -p "$P4ROOT"
        [ ! -d "$P4ROOT/root" ]     && mkdir -p "$P4ROOT/root"
        [ ! -d "$P4ROOT/root/ssl" ] && mkdir -p "$P4ROOT/root/ssl"
        [ ! -d "$P4ROOT/journals" ] && mkdir -p "$P4ROOT/journals"
        [ ! -d "$P4ROOT/logs" ]     && mkdir -p "$P4ROOT/logs"
        [ ! -d "$P4ROOT/archives" ] && mkdir -p "$P4ROOT/archives"

        # Ensure ownership is correct
        chown -R perforce:perforce "$P4ROOT"

        # Ensure permissions are secure
        chmod -R o=,g= "$P4ROOT"

        # The actual P4ROOT is a level down
        P4ROOT="$P4ROOT/root"

        initialize_db

        # Create SSL key and cert if required
        $SSL && gen_ssl_keys "$svr"

        save_server_env full "$cfg"

        # Enable unicode mode if requested.
        [ "$UNICODE" = y -o "$UNICODE" = Y -o "$UNICODE" = yes -o "$UNICODE" = true  -o "$UNICODE" = 0 ] && enable_unicode "$svr"

    else
        # Can change the port, but nothing else. Reload P4ROOT and P4SSLDIR

        # How is P4PORT configured?
        local portInCfg=false # Easy check
        local portInDbA=false  # -cshow
        local portInDbS=false  # -cshow
        local portInSvr=false # -cshow thisserver (must be 18.2)

        local cfgDb=$(p4dctl exec -f -t p4d "$svr" -- -cshow)
        local cfgSrv=$(p4dctl exec -f -t p4d "$svr" -- "-cshow thisserver")
        echo "$cfgSrv" | grep "^P4PORT\s*=.*" > /dev/null && portInSvr=true
        echo "$cfgDb" | grep "^any: P4PORT\s*=.*" > /dev/null && portInDbA=true
        echo "$cfgDb" | grep "^$svr: P4PORT\s*=.*" > /dev/null && portInDbS=true
        grep "^\s*P4PORT\s*=.*" "$cfg" > /dev/null && portInCfg=true

        if [ $portInDbA = true -o $portInDbS = true ]; then
            # Update the P4PORT by -cset
            local setSrv=any
            if [ $portInDbS = true ]; then
                setSrv=$svr
            fi
            p4dctl stop -t p4d "$svr" || true
            p4dctl exec -t p4d "$svr" -- "-cset $setSrv#P4PORT=$P4PORT" || true
        elif [ $portInSvr = true ]; then
            # Update the P4PORT in server spec (if we can)
            local oldPort=$(echo "$cfgSrv" | grep "^P4PORT\s*=.*" | egrep -o "[^ \t]*$")
            # This will only work if the server is up and we have credentials
            if ! p4 -u$P4USER -p$oldPort protects -m 2> /dev/null | grep "^super$"; then
                die "Need to be logged in as a superuser to perform this operation"
            fi
            p4 -u$P4USER -p$oldPort server -o "$svr" | sed -e "s/^Address:.*$/Address: $P4PORT/" | p4 -u$P4USER -p$oldPort server -i
            p4dctl stop -t p4d "$svr" || true
        elif [ $portInCfg = true ]; then
            # Update the P4PORT in the p4dctl config
            p4dctl stop -t p4d "$svr" || true
            save_server_env partial "$cfg"
        else
            die "Failed to change P4PORT: couldn't determine how P4PORT was set"
        fi

        # Create SSL key and cert if required
        load_server_env "$NAME"
        $SSL && gen_ssl_keys "$svr"

    fi

    p4dctl start -t p4d "$svr"

    # Safeguard for slow systems
    local attemps=0
    while $($P4 info 2>&1 | grep "Connect to server failed" > /dev/null); do
        sleep 1
        attemps=$[$attemps+1]
        if [ $attemps -gt 10 ]; then
            die "Server failed to start!"
        fi
    done

    # If it's not a fresh installation, we're done at this point
    if ! $FRESH_INSTALL; then
        $SSL && trust_server
        return 0
    fi

    initialize_repository "$svr"
}

P4IPPORT=""
get_full_port()
{
    P4IPPORT=""
    local IP=""
    if [ -e /sbin/ifconfig ]; then
        IP=$(/sbin/ifconfig 2>/dev/null | grep -o "inet addr:[^ ]*" | cut -d: -f2 | grep -v "^127" | head -n1)
    fi
    if [ -z "$IP" ] && [ -e /bin/ip ]; then
        IP=$(/bin/ip addr | grep -o "inet [^ ]*" | sed -e 's;.* \(.*\)/.*;\1;' | grep -v "^127" | head -n1)
    fi
    if [ -z "$IP" ] && [ -e /sbin/ip ]; then
        IP=$(/sbin/ip addr | grep -o "inet [^ ]*" | sed -e 's;.* \(.*\)/.*;\1;' | grep -v "^127" | head -n1)
    fi
    if [ -z "$IP" ]; then
       return
    fi
    $SSL && P4IPPORT="ssl:"
    P4IPPORT="$P4IPPORT$IP"
    P4IPPORT="$P4IPPORT:$(echo $P4PORT|sed -e 's/.*://')"
}


#-------------------------------------------------------------------------------
# Start of main functionality
#-------------------------------------------------------------------------------

# Prevent warnings from sudo if we are in a directory the target user
# does not have permission to be in. But store the original directory first.
SCRIPT="$(basename "$0")"
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
cd /
ensure_root "$@"

# Clear out P4 environment in case it gets polluted by existing settings
unset P4CONFIG P4PORT P4ROOT P4PASSWD P4SSLDIR P4CHARSET p4PORT p4ROOT p4USER SSL P4TRUST P4ENVIRO

# Default values for command-line
INTERACTIVE=true
UNICODE=n
NAME=""
AUTOUPGRADE=false
# y = 0 is case-sensitive.
CASE=y
[ -z "$Owner" ] && Owner=perforce
[ -z "$P4USER" ] && P4USER=super
[ -z "$Execute" ] && Execute=/opt/perforce/sbin/p4d

TEMP=$(getopt -n "configure-helix-p4d.sh" \
             -o "hnmp:r:u:P:" \
             -l "help,unicode,no-ssl,case:,debug,auto-upgrade" -- "$@")
if [ $? -ne 0 ] ; then
    usage
    exit 1
fi

# Reinject args from getopt, so now we know they're valid and in the
# right order.
eval set -- "$TEMP"

# From here on in, set -e, so if anything fails, the whole script dies.
# Doing it earlier would be good, but it messes with the getopt handling.
set -e

# Evaluate arguments.
while true ; do
    case "$1" in
        -h)             usage;             exit 0;;
        -n)             INTERACTIVE=false; shift;;
        -m)             MONOCHROME=true;   shift;;
        -p)             p4PORT=$2;         shift 2;;
        -r)             p4ROOT=$2;         shift 2;;
        -u)             p4USER=$2;         shift 2;;
        -P)             P4PASSWD=$2;       shift 2;;
        --no-ssl)       SSL=false;         shift;;
        --unicode)      oUNICODE=y;        shift;;
        --case)         oCASE=$2;          shift 2;;
        --debug)        DEBUG=true;        shift;;
        --auto-upgrade) AUTOUPGRADE=true;  shift;;
        --help)         usage;             exit 0;;
        --) shift ; break ;;
        *) die "Command-line syntax error!" ; exit 1 ;;
    esac
done

if [ $# -gt 1 ]; then
    usage
    exit 1
fi

echo

# Which server do they want to configure
[ $# -eq 1 ] && NAME=$1

if $INTERACTIVE || $DEBUG ; then
    highlight "Summary of arguments passed:\n"

    echo "Service-name        [${NAME:-(not specified)}]"
    echo "P4PORT              [${p4PORT:-(not specified)}]"
    echo "P4ROOT              [${p4ROOT:-(not specified)}]"
    echo "Super-user          [${p4USER:-(not specified)}]"
    echo "Super-user passwd   [${P4PASSWD:-(not specified)}]"
    echo "Unicode mode        [${oUNICODE:-(not specified)}]"
    echo "Case-sensitive      [${oCASE:-(not specified)}]"

    highlight "\nFor a list of other options, type Ctrl-C to exit, and then run:\n\$ sudo $SCRIPTPATH/$SCRIPT --help"
fi

# Which server do they want to configure
if [ -z "$NAME" ] || $INTERACTIVE ; then
    if $INTERACTIVE; then
        highlightOn
        cat <<!

You have entered interactive configuration for p4d. This script
will ask a series of questions, and use your answers to configure p4d
for first time use. Options passed in from the command line or
automatically discovered in the environment are presented as defaults.
You may press enter to accept them, or enter an alternative.

Please provide the following details about your desired P4 environment:

!
        highlightOff
        promptfor NAME "P4 Service name" false "${NAME:-master}" check_not_empty
    else
        die "Missing required environment details for non-interactive use"
    fi
fi

# Default values for new servers
P4PORT=ssl:1666
SSL=true
P4ROOT="/opt/perforce/servers/${NAME}"

# If the named server doesn't exist, create it
if ! server_exists "$NAME"; then
    echo "Service $NAME not found. Creating..."
fi

# Locate this server's p4dctl configuration file
server_config_file "$NAME"
CFG_FILE=$RET

# Load current configuration
load_server_env "$NAME"

# Is this a fresh installation or a reconfigure?
FRESH_INSTALL=true
server_initialized "$NAME" && FRESH_INSTALL=false

# Override with supplied params if any. P4ROOT can only be specified on
# the command-line for a fresh installation.
[ -n "$p4PORT" ] && P4PORT=$p4PORT
[ -n "$p4USER" ] && P4USER=$p4USER
[ -n "$oCASE"    ] && CASE=$oCASE
[ -n "$oUNICODE" ] && UNICODE=$oUNICODE
if $FRESH_INSTALL; then
    [ -n "$p4ROOT" ] && P4ROOT=$p4ROOT
else
    [ -z "$p4ROOT" ] || echo "Can't change P4ROOT for existing servers" >&2
fi

# Gather required information
$INTERACTIVE && fetch_p4_details "$NAME"
while ! check_p4_details "$NAME"; do
    if ! $INTERACTIVE; then
        die "Missing required environment details for non-interactive use"
    fi
    fetch_p4_details "$NAME"
done

# If P4PORT has ssl prefix, enable SSL; otherwise, disable.
if [ "${P4PORT#ssl:}" = "${P4PORT}" ]; then
    SSL=false
else
    SSL=true
fi

P4="/opt/perforce/bin/p4 -u$P4USER -p$P4PORT"

# Apply configuration changes
highlight "\nConfiguring p4d service '$NAME' with the information you specified...\n"
configure_server "$NAME" "$CFG_FILE"
get_full_port

highlightOn
cat <<!

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::
::  P4 Server configuration has completed successfully.
::
::  Here is what has been done so far:
::
::  - Your p4d service settings have been written to
::    the following p4dctl configuration file:
::      $CFG_FILE
!
if $FRESH_INSTALL ; then
   cat <<!
::  - The p4d service has been initialized with the P4ROOT:
::      $P4ROOT
::  - The p4d service has been started with the P4PORT: $P4PORT
::  - The p4d service has been set to Security Level 3.
::  - The new P4 super-user '$P4USER' has been created and the
::    password has been set to the one specified.
!
fi
cat <<!
::
::  Here is what you can do now:
::
::  - You can manage it with the '$Owner' user, using the following:
::
::      sudo -u $Owner p4dctl <cmd>
::
::  - You can connect to it by setting the P4PORT and P4USER
::    environment variables and running 'p4 <cmd>'. For example, run:
::
::      export P4PORT=$P4PORT
::      export P4USER=$P4USER
::
::      p4 login
::
::    For help, run:
::
::      p4 help
!
if [ -n "$P4IPPORT" ]; then
   cat <<!
::
::  - To connect to this p4d service from another machine, include
::    this machine's name or IP address in the P4PORT. For example:
::
::      export P4PORT=$P4IPPORT
!
fi
if $FRESH_INSTALL ; then
   cat <<!
::
::  - For help with creating P4 user accounts, populating the depot
::    with files, and making other customizations for your site, see
::    the P4 Server Administrator Guide:
::
::    https://www.perforce.com/perforce/doc.current/manuals/p4sag/index.html
!
fi
cat <<!
::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

!
highlightOff